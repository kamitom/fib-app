import pytest
from httpx import AsyncClient, ASGITransport
from unittest.mock import AsyncMock, MagicMock, patch
from main import app


@pytest.fixture
def mock_redis():
    """Mock Redis client."""
    mock = AsyncMock()
    mock.keys = AsyncMock(return_value=[])
    mock.mget = AsyncMock(return_value=[])
    mock.publish = AsyncMock()
    mock.close = AsyncMock()
    return mock


@pytest.fixture
def mock_pg_pool():
    """Mock PostgreSQL connection pool."""
    mock = AsyncMock()

    # Mock connection context manager
    mock_conn = AsyncMock()
    mock_conn.execute = AsyncMock()
    mock_conn.fetch = AsyncMock(return_value=[])

    # Mock acquire() context manager
    mock.acquire = MagicMock()
    mock.acquire.return_value.__aenter__ = AsyncMock(return_value=mock_conn)
    mock.acquire.return_value.__aexit__ = AsyncMock(return_value=None)

    mock.close = AsyncMock()
    return mock


@pytest.fixture
async def client(mock_redis, mock_pg_pool):
    """Create test client with mocked dependencies."""
    # Patch global connections before app lifespan
    with patch('main.redis.from_url', return_value=mock_redis), \
         patch('main.asyncpg.create_pool', return_value=mock_pg_pool):

        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test"
        ) as ac:
            # Inject mocks into app globals
            import main
            main.redis_client = mock_redis
            main.pg_pool = mock_pg_pool
            yield ac


class TestBasicEndpoints:
    """Test basic API endpoints."""

    @pytest.mark.asyncio
    async def test_root(self, client):
        response = await client.get("/")
        assert response.status_code == 200
        assert response.json() == {"message": "Fibonacci Multi-Container API"}

    @pytest.mark.asyncio
    async def test_health(self, client):
        response = await client.get("/health")
        assert response.status_code == 200
        assert response.json() == {"status": "ok"}


class TestGetAllIndices:
    """Test GET /values/all endpoint."""

    @pytest.mark.asyncio
    async def test_get_all_indices_empty(self, client, mock_pg_pool):
        # Mock empty result
        mock_conn = mock_pg_pool.acquire.return_value.__aenter__.return_value
        mock_conn.fetch.return_value = []

        response = await client.get("/values/all")
        assert response.status_code == 200
        assert response.json() == []

    @pytest.mark.asyncio
    async def test_get_all_indices_with_data(self, client, mock_pg_pool):
        # Mock database returning indices
        mock_conn = mock_pg_pool.acquire.return_value.__aenter__.return_value
        mock_conn.fetch.return_value = [
            {"number": 1},
            {"number": 5},
            {"number": 10}
        ]

        response = await client.get("/values/all")
        assert response.status_code == 200
        assert response.json() == [1, 5, 10]


class TestGetCurrentValues:
    """Test GET /values/current endpoint."""

    @pytest.mark.asyncio
    async def test_get_current_values_empty(self, client, mock_redis):
        mock_redis.keys.return_value = []

        response = await client.get("/values/current")
        assert response.status_code == 200
        assert response.json() == {}

    @pytest.mark.asyncio
    async def test_get_current_values_with_data(self, client, mock_redis):
        # Mock Redis returning calculated values
        mock_redis.keys.return_value = ["values.1", "values.5", "values.10"]
        mock_redis.mget.return_value = ["1", "5", "55"]

        response = await client.get("/values/current")
        assert response.status_code == 200

        data = response.json()
        assert data == {"1": "1", "5": "5", "10": "55"}


class TestSubmitIndex:
    """Test POST /values endpoint."""

    @pytest.mark.asyncio
    async def test_submit_valid_index(self, client, mock_pg_pool, mock_redis):
        mock_conn = mock_pg_pool.acquire.return_value.__aenter__.return_value

        response = await client.post("/values", json={"index": 10})
        assert response.status_code == 200
        assert response.json() == {"working": True, "index": 10}

        # Verify PostgreSQL insert was called
        mock_conn.execute.assert_called_once()
        call_args = mock_conn.execute.call_args[0]
        assert "INSERT INTO indices" in call_args[0]
        assert call_args[1] == 10

        # Verify Redis publish was called
        mock_redis.publish.assert_called_once_with("insert", "10")

    @pytest.mark.asyncio
    async def test_submit_zero_index(self, client, mock_pg_pool, mock_redis):
        """Zero is valid (edge case)."""
        response = await client.post("/values", json={"index": 0})
        assert response.status_code == 200
        assert response.json() == {"working": True, "index": 0}

    @pytest.mark.asyncio
    async def test_submit_max_index(self, client, mock_pg_pool, mock_redis):
        """Index 40 is the maximum allowed."""
        response = await client.post("/values", json={"index": 40})
        assert response.status_code == 200
        assert response.json() == {"working": True, "index": 40}

    @pytest.mark.asyncio
    async def test_submit_negative_index(self, client):
        response = await client.post("/values", json={"index": -1})
        assert response.status_code == 400
        assert "non-negative" in response.json()["detail"]

    @pytest.mark.asyncio
    async def test_submit_index_too_high(self, client):
        response = await client.post("/values", json={"index": 41})
        assert response.status_code == 422
        assert "too high" in response.json()["detail"].lower()

    @pytest.mark.asyncio
    async def test_submit_index_very_high(self, client):
        """Test boundary far beyond limit."""
        response = await client.post("/values", json={"index": 1000})
        assert response.status_code == 422

    @pytest.mark.asyncio
    async def test_submit_invalid_payload(self, client):
        """Missing 'index' field."""
        response = await client.post("/values", json={})
        assert response.status_code == 422

    @pytest.mark.asyncio
    async def test_submit_wrong_type(self, client):
        """Non-integer index."""
        response = await client.post("/values", json={"index": "abc"})
        assert response.status_code == 422


class TestDuplicateIndex:
    """Test handling of duplicate index submissions."""

    @pytest.mark.asyncio
    async def test_submit_duplicate_index(self, client, mock_pg_pool, mock_redis):
        """ON CONFLICT DO NOTHING should handle duplicates gracefully."""
        mock_conn = mock_pg_pool.acquire.return_value.__aenter__.return_value

        # Submit same index twice
        await client.post("/values", json={"index": 5})
        await client.post("/values", json={"index": 5})

        # Both should succeed (idempotent)
        assert mock_conn.execute.call_count == 2
        assert mock_redis.publish.call_count == 2
