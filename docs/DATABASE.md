# Database Schema Management

## Current Approach: CREATE IF NOT EXISTS

For this application, we use a **simple, practical approach** to database schema management:

```python
# fib-be/main.py (startup)
async with pg_pool.acquire() as conn:
    await conn.execute("""
        CREATE TABLE IF NOT EXISTS indices (
            number INTEGER PRIMARY KEY
        )
    """)
```

### Why Not Alembic?

**Schema Simplicity**: The entire database consists of ONE table with ONE column. Using a migration framework would be over-engineering.

**No Migration History Needed**:
- Table structure never changes
- No ALTER TABLE operations needed
- No complex migrations to rollback

**Deployment Simplicity**:
- New environments auto-initialize on first startup
- No separate migration commands to run
- Zero-downtime deployments (idempotent CREATE)

### When to Add Migrations

Consider adding Alembic/Flyway when:

1. **Schema grows beyond 3-4 tables**
2. **Need to track ALTER TABLE history** (column additions, renames, type changes)
3. **Multiple developers** need coordinated schema changes
4. **Rollback capability** becomes critical

### Current Schema

```sql
-- PostgreSQL Database: fib
CREATE TABLE indices (
    number INTEGER PRIMARY KEY  -- Fibonacci index requested by user
);

-- Indices are stored here for persistence
-- Values are calculated by worker and cached in Redis
```

### Redis Cache Schema

```
Key Pattern: values.{index}
Value: Fibonacci number as string

Example:
  values.10 = "89"
  values.20 = "10946"
```

### Backup & Recovery

**Development:**
```bash
# Backup
docker compose exec postgres pg_dump -U postgres fib > backup.sql

# Restore
docker compose exec -T postgres psql -U postgres fib < backup.sql
```

**Production (AWS RDS):**
- Automated daily snapshots
- Point-in-time recovery (PITR)
- Manual snapshots before deployments

### Testing Strategy

**Unit Tests**: Mock database (AsyncMock for asyncpg pool)

**Integration Tests**: Real PostgreSQL container via docker compose

See: [tests/test_integration.py](../tests/test_integration.py)
