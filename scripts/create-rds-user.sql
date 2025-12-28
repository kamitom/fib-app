-- Create new user fib_staging
CREATE USER fib_staging WITH PASSWORD 'Test12345678';

-- Grant all privileges on database
GRANT ALL PRIVILEGES ON DATABASE fib_staging TO fib_staging;

-- Connect to fib_staging database and grant schema privileges
\c fib_staging

-- Grant all privileges on all tables in public schema
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO fib_staging;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO fib_staging;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO fib_staging;

-- Grant privileges on future tables (for newly created tables)
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON TABLES TO fib_staging;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON SEQUENCES TO fib_staging;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON FUNCTIONS TO fib_staging;

-- Grant schema usage and creation
GRANT USAGE, CREATE ON SCHEMA public TO fib_staging;

-- Make fib_staging owner of the schema (optional, for full control)
-- ALTER SCHEMA public OWNER TO fib_staging;

-- Verify the user was created
\du fib_staging
