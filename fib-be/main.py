import os
import asyncio
import time
import ssl
from contextlib import asynccontextmanager
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import redis.asyncio as redis
import asyncpg


# Environment variables
REDIS_HOST = os.getenv("REDIS_HOST", "redis")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
PGUSER = os.getenv("PGUSER", "postgres")
PGHOST = os.getenv("PGHOST", "postgres")
PGDATABASE = os.getenv("PGDATABASE", "fib")
PGPASSWORD = os.getenv("PGPASSWORD", "postgres")
PGPORT = int(os.getenv("PGPORT", "5432"))
PGSSL = os.getenv("PGSSL", "disable")  # "require" for AWS RDS, "disable" for local


# Global connections
redis_client: redis.Redis = None
pg_pool: asyncpg.Pool = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Initialize connections on startup with retries, cleanup on shutdown."""
    global redis_client, pg_pool

    # Connect to Redis with retries
    max_retries = 5
    for attempt in range(max_retries):
        try:
            redis_client = await redis.from_url(
                f"redis://{REDIS_HOST}:{REDIS_PORT}",
                decode_responses=True
            )
            print(f"✓ Connected to Redis on attempt {attempt + 1}")
            break
        except Exception as e:
            if attempt < max_retries - 1:
                wait_time = 2 ** attempt  # Exponential backoff
                print(f"Redis connection attempt {attempt + 1} failed: {e}. Retrying in {wait_time}s...")
                await asyncio.sleep(wait_time)
            else:
                raise

    # Connect to PostgreSQL with retries
    for attempt in range(max_retries):
        try:
            # Prepare connection parameters
            conn_params = {
                "user": PGUSER,
                "password": PGPASSWORD,
                "database": PGDATABASE,
                "host": PGHOST,
                "port": PGPORT,
                "timeout": 5
            }

            # Add SSL if required (AWS RDS)
            if PGSSL == "require":
                # Create SSL context that doesn't verify certificates
                # AWS RDS requires SSL but self-signed certs need verification disabled
                ssl_context = ssl.create_default_context()
                ssl_context.check_hostname = False
                ssl_context.verify_mode = ssl.CERT_NONE
                conn_params["ssl"] = ssl_context

            pg_pool = await asyncpg.create_pool(**conn_params)
            print(f"✓ Connected to PostgreSQL on attempt {attempt + 1}")
            break
        except asyncpg.InvalidPasswordError as e:
            # If fib_staging user auth fails, try to create it with master user
            if PGUSER == "fib_staging" and attempt == 0:
                print(f"⚠️  User {PGUSER} auth failed, attempting to create user with master account...")
                try:
                    master_params = conn_params.copy()
                    master_params["user"] = "mac398"
                    master_conn = await asyncpg.connect(**master_params)

                    # Check if user exists
                    user_exists = await master_conn.fetchval(
                        "SELECT 1 FROM pg_roles WHERE rolname = $1", PGUSER
                    )

                    if not user_exists:
                        print(f"Creating user {PGUSER}...")
                        await master_conn.execute(f"CREATE USER {PGUSER} WITH PASSWORD $1", PGPASSWORD)
                        await master_conn.execute(f"GRANT ALL PRIVILEGES ON DATABASE {PGDATABASE} TO {PGUSER}")
                        await master_conn.execute(f"GRANT USAGE, CREATE ON SCHEMA public TO {PGUSER}")
                        await master_conn.execute(f"GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO {PGUSER}")
                        await master_conn.execute(f"GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO {PGUSER}")
                        await master_conn.execute(f"ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON TABLES TO {PGUSER}")
                        await master_conn.execute(f"ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON SEQUENCES TO {PGUSER}")
                        print(f"✓ User {PGUSER} created successfully")
                    else:
                        print(f"✓ User {PGUSER} exists, updating password...")
                        await master_conn.execute(f"ALTER USER {PGUSER} WITH PASSWORD $1", PGPASSWORD)

                    await master_conn.close()
                    # Retry connection with the newly created/updated user
                    continue
                except Exception as create_error:
                    print(f"❌ Failed to create user: {create_error}")
                    if attempt < max_retries - 1:
                        wait_time = 2 ** attempt
                        await asyncio.sleep(wait_time)
                    else:
                        raise
            else:
                raise e
        except Exception as e:
            if attempt < max_retries - 1:
                wait_time = 2 ** attempt
                print(f"PostgreSQL connection attempt {attempt + 1} failed: {e}. Retrying in {wait_time}s...")
                await asyncio.sleep(wait_time)
            else:
                raise

    # Ensure table exists
    async with pg_pool.acquire() as conn:
        await conn.execute("""
            CREATE TABLE IF NOT EXISTS indices (
                number INTEGER PRIMARY KEY
            )
        """)

    yield

    # Cleanup
    await redis_client.close()
    await pg_pool.close()


app = FastAPI(lifespan=lifespan)

# CORS for frontend
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


class IndexRequest(BaseModel):
    index: int


@app.get("/")
def root():
    return {"message": "Fibonacci Multi-Container API"}


@app.get("/values/all")
async def get_all_indices():
    """Get all indices from PostgreSQL."""
    async with pg_pool.acquire() as conn:
        rows = await conn.fetch("SELECT number FROM indices ORDER BY number")
        return [row["number"] for row in rows]


@app.get("/values/current")
async def get_current_values():
    """Get all calculated values from Redis."""
    keys = await redis_client.keys("values.*")
    if not keys:
        return {}

    values = await redis_client.mget(keys)
    result = {}
    for key, value in zip(keys, values):
        index = key.split(".")[-1]
        result[index] = value

    return result


@app.post("/values")
async def submit_index(req: IndexRequest):
    """Submit new index for calculation."""
    index = req.index

    # Validation
    if index < 0:
        raise HTTPException(status_code=400, detail="Index must be non-negative")

    if index > 40:
        raise HTTPException(status_code=422, detail="Index too high (max 40)")

    # Store in PostgreSQL
    async with pg_pool.acquire() as conn:
        await conn.execute(
            "INSERT INTO indices (number) VALUES ($1) ON CONFLICT DO NOTHING",
            index
        )

    # Publish to Redis for worker
    await redis_client.publish("insert", str(index))

    return {"working": True, "index": index}


@app.get("/health")
async def health():
    """Health check endpoint that verifies all dependencies."""
    checks = {
        "api": "healthy",
        "redis": "unknown",
        "postgres": "unknown"
    }

    # Check Redis
    try:
        await redis_client.ping()
        checks["redis"] = "healthy"
    except Exception as e:
        checks["redis"] = f"unhealthy: {str(e)}"

    # Check PostgreSQL
    try:
        async with pg_pool.acquire() as conn:
            await conn.fetchval("SELECT 1")
        checks["postgres"] = "healthy"
    except Exception as e:
        checks["postgres"] = f"unhealthy: {str(e)}"

    # Overall status
    all_healthy = all(v == "healthy" for v in checks.values())

    return {
        "status": "healthy" if all_healthy else "degraded",
        "checks": checks
    }
