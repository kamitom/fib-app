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
docker compose up -d

# 訪問應用
http://localhost:30003

# 查看 health checks
curl http://localhost:30003/api/health
curl http://localhost:5001/health
```

### 執行測試
```bash
# 所有測試（需要 docker compose up -d）
./test-all.sh

# 個別測試
cd fib-fe && npm run test:unit              # 前端測試 (12 tests)
cd fib-be && pytest test_main.py -v         # 後端測試 (19 tests)
cd fib-worker && npm test                   # Worker 測試 (13 tests)
pytest tests/test_integration.py -v          # 整合測試 (10 tests)
```

**總計：54 tests**
- Unit tests: 44 (frontend 12 + backend 19 + worker 13)
- Integration tests: 10 (multi-container E2E tests)

詳細測試文件請參考 [TESTING.md](TESTING.md)

## CI/CD 狀態

### ✅ CI 階段完成

**GitHub Actions Workflows:**
- **CI Pipeline**: 自動執行 44 個 unit tests + Docker builds
- **Test Coverage**: 前端 97.91% coverage
- **Lint**: TypeScript type checking + Python ruff

**分支策略:**
- `main`: Production 部署
- `develop`: Staging 部署
- `feature/**`: 自動 CI 檢查

### 🚧 CD 階段準備中

**✅ 已完成（選項 B - 穩健路線）:**

1. **Health Check Endpoints**
   - Backend: `/health` 檢查 API、Redis、PostgreSQL ([fib-be/main.py:130](fib-be/main.py#L130))
   - Worker: `:5001/health` 檢查 worker、Redis ([fib-worker/index.js:20](fib-worker/index.js#L20))
   - 新增 4 個 health check 測試

2. **Integration Tests**
   - 10 個 multi-container E2E 測試 ([tests/test_integration.py](tests/test_integration.py))
   - 測試完整 Fibonacci 流程：submit → PostgreSQL → Redis pub/sub → worker calculation
   - 測試 Nginx reverse proxy 路由

3. **Database Schema Management**
   - 採用 `CREATE TABLE IF NOT EXISTS` 方案（適合單表架構）
   - 文件化遷移策略 ([docs/DATABASE.md](docs/DATABASE.md))

4. **Environment Configurations**
   - `.env.staging.example` - Staging 環境模板
   - `.env.production.example` - Production 環境模板
   - 更新 `.gitignore` 防止洩漏

5. **Deployment Documentation**
   - 完整 AWS Elastic Beanstalk 部署指南 ([docs/DEPLOYMENT.md](docs/DEPLOYMENT.md))
   - Infrastructure 設置步驟（RDS、ElastiCache、ECR）
   - GitHub Actions CD workflow 範本

**⬜ 下一步（準備進入 CD）:**
- [ ] 建立 `Dockerrun.aws.json` for Elastic Beanstalk
- [ ] 設置 AWS 基礎設施（RDS PostgreSQL、ElastiCache Redis、ECR）
- [ ] 配置 GitHub Secrets（AWS credentials、RDS/Redis endpoints）
- [ ] 建立 `.github/workflows/deploy-staging.yml`
- [ ] 建立 `.github/workflows/deploy-production.yml`
- [ ] 測試 staging 環境部署
- [ ] 設置監控與告警（CloudWatch）

### 部署目標
- ✅ **AWS Elastic Beanstalk** (推薦 - 原生支援 multi-container)
- 🔄 GCP Compute Engine + Docker Compose
- ⚠️ GCP Cloud Run (需要重構架構為微服務)

參考：[DEPLOYMENT.md](docs/DEPLOYMENT.md) 查看完整部署指南
