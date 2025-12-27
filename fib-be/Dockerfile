FROM python:3.12-alpine

WORKDIR /usr/fib-be

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8000

# 生產預設：無 --reload
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
