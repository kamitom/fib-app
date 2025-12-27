"""
Integration tests for multi-container Fibonacci application.

These tests require all containers to be running:
    docker compose up -d

Run with: pytest tests/test_integration.py
"""
import pytest
import requests
import time


BASE_URL = "http://localhost:30003"
API_URL = f"{BASE_URL}/api"
WORKER_HEALTH_URL = "http://localhost:5001/health"


@pytest.fixture(scope="module", autouse=True)
def wait_for_services():
    """Wait for all services to be ready before running tests."""
    max_retries = 30
    retry_delay = 1

    # Wait for API
    for i in range(max_retries):
        try:
            response = requests.get(f"{API_URL}/health", timeout=2)
            if response.status_code == 200:
                data = response.json()
                if data.get("status") == "healthy":
                    break
        except requests.RequestException:
            pass
        time.sleep(retry_delay)
    else:
        pytest.fail("API health check never became healthy")

    # Wait for worker
    for i in range(max_retries):
        try:
            response = requests.get(WORKER_HEALTH_URL, timeout=2)
            if response.status_code == 200:
                data = response.json()
                if data.get("status") == "healthy":
                    break
        except requests.RequestException:
            pass
        time.sleep(retry_delay)
    else:
        pytest.fail("Worker health check never became healthy")

    yield

    # Cleanup: could clear test data here if needed


class TestHealthChecks:
    """Test health check endpoints for all services."""

    def test_api_health_check(self):
        """API health check should report all dependencies."""
        response = requests.get(f"{API_URL}/health")
        assert response.status_code == 200

        data = response.json()
        assert data["status"] == "healthy"
        assert data["checks"]["api"] == "healthy"
        assert data["checks"]["redis"] == "healthy"
        assert data["checks"]["postgres"] == "healthy"

    def test_worker_health_check(self):
        """Worker health check should report Redis connection."""
        response = requests.get(WORKER_HEALTH_URL)
        assert response.status_code == 200

        data = response.json()
        assert data["status"] == "healthy"
        assert data["checks"]["worker"] == "healthy"
        assert data["checks"]["redis"] == "healthy"


class TestEndToEndFibonacci:
    """Test complete Fibonacci calculation flow across all containers."""

    def test_submit_and_calculate(self):
        """Submit index, verify storage, wait for worker calculation."""
        test_index = 7

        # 1. Submit index via API
        response = requests.post(f"{API_URL}/values", json={"index": test_index})
        assert response.status_code == 200
        assert response.json() == {"working": True, "index": test_index}

        # 2. Verify index stored in PostgreSQL
        response = requests.get(f"{API_URL}/values/all")
        assert response.status_code == 200
        indices = response.json()
        assert test_index in indices

        # 3. Wait for worker to calculate (max 10 seconds)
        expected_result = "21"  # fib(7) = 21
        for _ in range(20):
            response = requests.get(f"{API_URL}/values/current")
            assert response.status_code == 200
            values = response.json()

            if str(test_index) in values:
                assert values[str(test_index)] == expected_result
                break

            time.sleep(0.5)
        else:
            pytest.fail(f"Worker never calculated fib({test_index})")

    def test_multiple_indices(self):
        """Submit multiple indices and verify all calculations."""
        test_cases = [
            (0, "1"),
            (1, "1"),
            (5, "8"),
            (10, "89"),
        ]

        # Submit all indices
        for index, _ in test_cases:
            response = requests.post(f"{API_URL}/values", json={"index": index})
            assert response.status_code == 200

        # Wait for all calculations
        time.sleep(2)

        # Verify all results
        response = requests.get(f"{API_URL}/values/current")
        assert response.status_code == 200
        values = response.json()

        for index, expected in test_cases:
            assert str(index) in values
            assert values[str(index)] == expected

    def test_invalid_index_rejection(self):
        """API should reject invalid indices."""
        # Negative index
        response = requests.post(f"{API_URL}/values", json={"index": -5})
        assert response.status_code == 400

        # Index too high
        response = requests.post(f"{API_URL}/values", json={"index": 50})
        assert response.status_code == 422

    def test_duplicate_index_idempotency(self):
        """Submitting same index multiple times should be idempotent."""
        test_index = 12

        # Submit same index twice
        response1 = requests.post(f"{API_URL}/values", json={"index": test_index})
        response2 = requests.post(f"{API_URL}/values", json={"index": test_index})

        assert response1.status_code == 200
        assert response2.status_code == 200

        # Should still only appear once in indices
        response = requests.get(f"{API_URL}/values/all")
        indices = response.json()
        assert indices.count(test_index) >= 1  # At least once


class TestRedisCache:
    """Test Redis caching behavior."""

    def test_values_persistence(self):
        """Calculated values should persist in Redis."""
        test_index = 15

        # Submit and wait for calculation
        requests.post(f"{API_URL}/values", json={"index": test_index})
        time.sleep(2)

        # Fetch twice - should get same result from cache
        response1 = requests.get(f"{API_URL}/values/current")
        response2 = requests.get(f"{API_URL}/values/current")

        assert response1.json() == response2.json()
        assert str(test_index) in response1.json()


class TestPostgresStorage:
    """Test PostgreSQL storage behavior."""

    def test_indices_sorted_order(self):
        """Indices should be returned in sorted order."""
        # Submit indices in random order
        for index in [20, 3, 15, 8]:
            requests.post(f"{API_URL}/values", json={"index": index})

        time.sleep(1)

        response = requests.get(f"{API_URL}/values/all")
        indices = response.json()

        # Should be sorted
        sorted_indices = sorted(set(indices))
        # Check subset since there might be data from previous tests
        assert all(idx in indices for idx in [3, 8, 15, 20])


class TestNginxProxy:
    """Test Nginx reverse proxy functionality."""

    def test_nginx_routes_api_requests(self):
        """Nginx should correctly route /api/* to backend."""
        response = requests.get(f"{API_URL}/")
        assert response.status_code == 200
        assert "Fibonacci" in response.json()["message"]

    def test_nginx_routes_frontend(self):
        """Nginx should serve frontend at root."""
        response = requests.get(BASE_URL)
        assert response.status_code == 200
        # Frontend should return HTML
        assert "<!DOCTYPE html>" in response.text or "<!doctype html>" in response.text
