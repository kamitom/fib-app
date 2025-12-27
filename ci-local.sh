#!/bin/bash
# 模擬 GitHub Actions CI 環境的本地測試腳本

echo "==========================================="
echo "🚀 Local CI Simulation"
echo "==========================================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Track failures
FAILURES=0

# Get absolute path to project root
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

run_job() {
  local job_name=$1
  local command=$2

  echo -e "${YELLOW}▶ Running: ${job_name}${NC}"

  if (cd "$PROJECT_ROOT" && eval "$command"); then
    echo -e "${GREEN}✓ ${job_name} passed${NC}"
    echo ""
  else
    echo -e "${RED}✗ ${job_name} failed${NC}"
    echo ""
    FAILURES=$((FAILURES + 1))
  fi
}

# Frontend Job
echo "==========================================="
echo "Job: test-frontend"
echo "==========================================="
run_job "Frontend - Install" "cd fib-fe && npm ci --silent"
run_job "Frontend - Tests" "cd fib-fe && npm run test:unit -- --run"
run_job "Frontend - Type Check" "cd fib-fe && npm run type-check"
run_job "Frontend - Build" "cd fib-fe && npm run build"

# Backend Job
echo "==========================================="
echo "Job: test-backend"
echo "==========================================="
run_job "Backend - Install" "cd fib-be && pip install -q -r requirements.txt"
run_job "Backend - Tests" "cd fib-be && python -m pytest test_main.py -v --tb=short"

# Worker Job
echo "==========================================="
echo "Job: test-worker"
echo "==========================================="
run_job "Worker - Install" "cd fib-worker && npm ci --silent"
run_job "Worker - Tests" "cd fib-worker && npm test"

# Docker Build Job
echo "==========================================="
echo "Job: build-images"
echo "==========================================="
run_job "Build - Frontend" "docker build -q -t fib-fe:latest ./fib-fe"
run_job "Build - Backend" "docker build -q -t fib-be:latest ./fib-be"
run_job "Build - Worker" "docker build -q -t fib-worker:latest ./fib-worker"
run_job "Build - Nginx" "docker build -q -t fib-nginx:latest ./nginx"

# Integration Tests Job (optional - requires containers running)
echo "==========================================="
echo "Job: integration-tests (optional)"
echo "==========================================="
if docker compose ps | grep -q "Up"; then
  echo "Docker containers detected - running integration tests"
  run_job "Integration Tests - Install" "pip install -q -r tests/requirements.txt"
  run_job "Integration Tests - Run" "python -m pytest tests/test_integration.py -v --tb=short"
else
  echo -e "${YELLOW}⚠️  Skipping integration tests (containers not running)${NC}"
  echo "To run: docker compose up -d && ./ci-local.sh"
  echo ""
fi

# Summary
echo "==========================================="
if [ $FAILURES -eq 0 ]; then
  echo -e "${GREEN}✓ All jobs passed!${NC}"
  echo "==========================================="
  exit 0
else
  echo -e "${RED}✗ $FAILURES job(s) failed${NC}"
  echo "==========================================="
  exit 1
fi
