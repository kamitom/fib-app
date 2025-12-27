import os
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


# Global connections
redis_client: redis.Redis = None
pg_pool: asyncpg.Pool = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Initialize connections on startup, cleanup on shutdown."""
    global redis_client, pg_pool

    # Connect to Redis
    redis_client = await redis.from_url(
        f"redis://{REDIS_HOST}:{REDIS_PORT}",
        decode_responses=True
    )

    # Connect to PostgreSQL
    pg_pool = await asyncpg.create_pool(
        user=PGUSER,
        password=PGPASSWORD,
        database=PGDATABASE,
        host=PGHOST,
        port=PGPORT
    )

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
