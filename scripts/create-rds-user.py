#!/usr/bin/env python3
"""
Create fib_staging user in RDS PostgreSQL database.
This script should be run from within the AWS VPC (e.g., from an EC2 instance or ECS container).
"""
import asyncio
import asyncpg
import ssl
import sys

# RDS connection details
RDS_HOST = "fib-app-staging-db.c1qec0cgmaei.ap-northeast-1.rds.amazonaws.com"
RDS_PORT = 5432
MASTER_USER = "mac398"
MASTER_PASSWORD = "Test12345678"
DATABASE = "fib_staging"

# New user details
NEW_USER = "fib_staging"
NEW_PASSWORD = "Test12345678"


async def create_user():
    """Create fib_staging user with full privileges."""
    # Create SSL context
    ssl_context = ssl.create_default_context()
    ssl_context.check_hostname = False
    ssl_context.verify_mode = ssl.CERT_NONE

    try:
        # Connect as master user
        print(f"Connecting to RDS as {MASTER_USER}...")
        conn = await asyncpg.connect(
            user=MASTER_USER,
            password=MASTER_PASSWORD,
            database=DATABASE,
            host=RDS_HOST,
            port=RDS_PORT,
            ssl=ssl_context,
            timeout=10
        )
        print("✅ Connected successfully")

        # Check if user already exists
        print(f"\nChecking if user {NEW_USER} exists...")
        existing = await conn.fetchval(
            "SELECT 1 FROM pg_roles WHERE rolname = $1",
            NEW_USER
        )

        if existing:
            print(f"⚠️  User {NEW_USER} already exists. Updating password...")
            await conn.execute(
                f"ALTER USER {NEW_USER} WITH PASSWORD $1",
                NEW_PASSWORD
            )
        else:
            print(f"Creating user {NEW_USER}...")
            await conn.execute(
                f"CREATE USER {NEW_USER} WITH PASSWORD $1",
                NEW_PASSWORD
            )

        print(f"✅ User {NEW_USER} created/updated")

        # Grant database privileges
        print(f"\nGranting privileges on database {DATABASE}...")
        await conn.execute(f"GRANT ALL PRIVILEGES ON DATABASE {DATABASE} TO {NEW_USER}")
        print("✅ Database privileges granted")

        # Grant schema privileges
        print("\nGranting schema privileges...")
        await conn.execute(f"GRANT USAGE, CREATE ON SCHEMA public TO {NEW_USER}")
        await conn.execute(f"GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO {NEW_USER}")
        await conn.execute(f"GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO {NEW_USER}")
        await conn.execute(f"GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO {NEW_USER}")
        print("✅ Schema privileges granted")

        # Grant default privileges for future objects
        print("\nGranting default privileges for future objects...")
        await conn.execute(
            f"ALTER DEFAULT PRIVILEGES IN SCHEMA public "
            f"GRANT ALL PRIVILEGES ON TABLES TO {NEW_USER}"
        )
        await conn.execute(
            f"ALTER DEFAULT PRIVILEGES IN SCHEMA public "
            f"GRANT ALL PRIVILEGES ON SEQUENCES TO {NEW_USER}"
        )
        await conn.execute(
            f"ALTER DEFAULT PRIVILEGES IN SCHEMA public "
            f"GRANT ALL PRIVILEGES ON FUNCTIONS TO {NEW_USER}"
        )
        print("✅ Default privileges granted")

        # Verify the user
        print(f"\nVerifying user {NEW_USER}...")
        user_info = await conn.fetchrow(
            """
            SELECT rolname, rolsuper, rolcreatedb, rolcreaterole
            FROM pg_roles
            WHERE rolname = $1
            """,
            NEW_USER
        )
        print(f"User info: {dict(user_info)}")

        await conn.close()
        print(f"\n✅ User {NEW_USER} is ready to use!")
        print(f"\nConnection details:")
        print(f"  Host: {RDS_HOST}")
        print(f"  Port: {RDS_PORT}")
        print(f"  Database: {DATABASE}")
        print(f"  Username: {NEW_USER}")
        print(f"  Password: {NEW_PASSWORD}")

        return True

    except Exception as e:
        print(f"\n❌ Error: {type(e).__name__}: {e}")
        return False


if __name__ == "__main__":
    success = asyncio.run(create_user())
    sys.exit(0 if success else 1)
