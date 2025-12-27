# 這是一個學習什麼是多容器化應用程式的專案

![CI](https://github.com/YOUR_USERNAME/fib-app/workflows/CI/badge.svg)
![Test Coverage](https://github.com/YOUR_USERNAME/fib-app/workflows/Test%20Coverage/badge.svg)

## 專案功能： 斐波那契數列（Fibonacci sequence）web app

## 這是 multi-container Application

### 系統架構
- **前端**: Vue3 Server
- **後端**: FastAPI
- **反向代理**: Nginx
- **快取層**: Redis（存儲索引和計算結果）
- **資料庫**: PostgreSQL（持久化存儲已計算過的索引）
- **背景工作**: Worker（監聽 Redis 的新索引，執行計算並回存）

### User Story
使用者透過 Fibonacci Calculator 網頁介面輸入索引數字，系統會：
1. 前端 Vue3 應用接收使用者輸入
2. FastAPI 後端處理請求
3. Redis 快取層存儲所有索引及其對應的計算值
4. Worker 後台監聽新索引，執行計算並將結果存回 Redis
5. PostgreSQL 持久化保存已計算過的索引列表

詳細的架構流程圖和 User Story 圖示請參考 [USER-STORY](USER-STORY/) 目錄

## 開發與測試

### 本地開發
```bash
# 啟動所有服務
docker-compose up

# 訪問應用
http://localhost:30003
```

### 執行測試
```bash
# 所有測試
./test-all.sh

# 個別測試
cd fib-fe && npm run test:unit      # 前端測試
cd fib-be && pytest -v               # 後端測試
cd fib-worker && npm test            # Worker 測試
```

詳細測試文件請參考 [TESTING.md](TESTING.md)

## CI/CD

### GitHub Actions
- **CI Pipeline**: 自動執行所有測試
- **Test Coverage**: 程式碼覆蓋率報告
- **Docker Build**: 驗證所有容器映像可以成功構建

### 部署目標
- ✅ **AWS Elastic Beanstalk** (推薦 - 原生支援 multi-container)
- 🔄 GCP Compute Engine + Docker Compose
- ⚠️ GCP Cloud Run (需要重構架構為微服務)
