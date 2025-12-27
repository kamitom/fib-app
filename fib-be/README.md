# Fibonacci API

Simple FastAPI service for fibonacci calculations.

## Setup

```bash
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
pip install -r requirements.txt
```

## Run

```bash
uvicorn main:app --reload
```

API will be available at: http://localhost:8000

## API Docs

Interactive docs: http://localhost:8000/docs

## Endpoints

- `GET /` - Health check
- `POST /fib` - Calculate fibonacci
  ```json
  {"n": 10}
  ```
- `GET /health` - Service status
