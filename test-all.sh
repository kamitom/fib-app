#!/bin/bash
set -e

echo "========================================="
echo "Running all tests for fib-app"
echo "========================================="

# Frontend tests
echo ""
echo "📦 Frontend Tests (Vue + Vitest)..."
cd fib-fe
npm install --silent
npm run test:unit -- --run
cd ..

# Backend tests
echo ""
echo "🐍 Backend Tests (FastAPI + pytest)..."
cd fib-be
pip install -q -r requirements.txt
python -m pytest test_main.py -v
cd ..

# Worker tests
echo ""
echo "⚙️  Worker Tests (Node + Jest)..."
cd fib-worker
npm install --silent
npm test
cd ..

# Integration tests (requires docker compose up)
echo ""
echo "🔗 Integration Tests (Multi-container)..."
echo "⚠️  Note: Requires 'docker compose up -d' to be running"
pip install -q -r tests/requirements.txt
python -m pytest tests/test_integration.py -v

echo ""
echo "========================================="
echo "✅ All tests passed!"
echo "========================================="
