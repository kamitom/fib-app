# AGENTS.md

This file provides quick, project-specific guidance for coding agents.

## Project overview
- Multi-container Fibonacci web app.
- Services: Vue3 client, FastAPI API, Redis, PostgreSQL, worker, Nginx reverse proxy.

## Key entrypoints
- docker-compose: `docker-compose.yml`
- API: `fib-be/main.py`
- Worker: `fib-worker/index.js`
- Nginx config: `nginx/default.conf`

## Local development
- Start: `docker compose up -d`
- App: `http://localhost:30003`
- Health: `http://localhost:30003/api/health`, `http://localhost:5001/health`

## Tests
- All: `./test-all.sh`
- Frontend: `cd fib-fe && npm run test:unit`
- Backend: `cd fib-be && pytest test_main.py -v`
- Worker: `cd fib-worker && npm test`
- Integration: `pytest tests/test_integration.py -v`

## Deployment
- Target: AWS Elastic Beanstalk multi-container.
- Docs: `docs/DEPLOYMENT.md`, `docs/QUICK-START-CD.md`
- Dockerrun template: `Dockerrun.aws.json.template`

## Agent notes
- Keep production changes aligned with `Dockerrun.aws.json.template`.
- Avoid hardcoding secrets; use environment variables.
- Nginx uses Docker DNS resolver (`127.0.0.11`) with variable `proxy_pass` to avoid startup failures when upstreams are not yet resolvable.
