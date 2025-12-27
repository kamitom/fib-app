# CD 部署檢查清單

## 📋 Staging 環境部署

### 前置準備

- [ ] AWS 帳號已建立
- [ ] AWS CLI 已安裝並設定 (`aws configure`)
- [ ] 確認 IAM 使用者具備所需權限
- [ ] 本地已完成所有測試（54 tests 全過）
- [ ] CI pipeline 全部通過（GitHub Actions）

### AWS 基礎設施建立（約 20 分鐘）

- [ ] 執行 `./scripts/setup-aws-infrastructure.sh` 選擇 Staging
- [ ] 輸入資料庫使用者名稱和密碼
- [ ] 等待 RDS PostgreSQL 建立完成
- [ ] 等待 ElastiCache Redis 建立完成
- [ ] 確認 4 個 ECR repositories 已建立
- [ ] 記錄輸出的 endpoints 和 credentials

### Elastic Beanstalk 環境建立（約 5 分鐘）

- [ ] 登入 AWS Console > Elastic Beanstalk
- [ ] Create new environment
  - [ ] Application name: `fib-app`
  - [ ] Environment name: `fib-app-staging`
  - [ ] Platform: Docker > Multi-container Docker
  - [ ] Environment type: Load balanced
  - [ ] EC2 instance type: `t3.small`
- [ ] Network 設定
  - [ ] 選擇 default VPC
  - [ ] 選擇至少 2 個 public subnets
  - [ ] EC2 security group: `fib-app-staging-eb-sg`
- [ ] Monitoring
  - [ ] Health reporting: Enhanced
  - [ ] Managed updates: Enabled
- [ ] 點擊 Create environment
- [ ] 等待環境建立完成（約 5 分鐘）

### GitHub Secrets 設定（約 2 分鐘）

前往 GitHub repository > Settings > Secrets and variables > Actions

- [ ] `AWS_ACCESS_KEY_ID` - IAM 使用者 Access Key
- [ ] `AWS_SECRET_ACCESS_KEY` - IAM 使用者 Secret Key
- [ ] `AWS_ACCOUNT_ID` - 12 位數 AWS Account ID
- [ ] `AWS_REGION` - `ap-northeast-1`
- [ ] `ECR_REGISTRY` - `<account-id>.dkr.ecr.ap-northeast-1.amazonaws.com`
- [ ] `STAGING_RDS_ENDPOINT` - 從腳本輸出取得
- [ ] `STAGING_REDIS_ENDPOINT` - 從腳本輸出取得
- [ ] `STAGING_DB_PASSWORD` - 資料庫密碼

### 部署執行（約 10 分鐘）

- [ ] 建立 develop 分支：`git checkout -b develop`
- [ ] 推送至 GitHub：`git push -u origin develop`
- [ ] 前往 GitHub Actions 查看 "Deploy to Staging" workflow
- [ ] 確認所有步驟通過：
  - [ ] Build Docker images
  - [ ] Push to ECR
  - [ ] Generate Dockerrun.aws.json
  - [ ] Deploy to Elastic Beanstalk
  - [ ] Health check passed

### 驗證部署（約 2 分鐘）

- [ ] 取得環境 URL：
  ```bash
  aws elasticbeanstalk describe-environments \
    --application-name fib-app \
    --environment-names fib-app-staging \
    --region ap-northeast-1 \
    --query 'Environments[0].CNAME' \
    --output text
  ```
- [ ] 測試 health check：`curl http://<url>/api/health`
- [ ] 驗證回應包含：
  ```json
  {
    "status": "healthy",
    "checks": {
      "api": "healthy",
      "redis": "healthy",
      "postgres": "healthy"
    }
  }
  ```
- [ ] 訪問前端：`http://<url>`
- [ ] 測試 Fibonacci 計算功能
- [ ] 確認 worker 正常處理任務

### 測試功能（約 3 分鐘）

```bash
# 提交計算請求
curl -X POST http://<url>/api/values \
  -H "Content-Type: application/json" \
  -d '{"index": 7}'

# 查看所有索引
curl http://<url>/api/values/all

# 等待 worker 計算（約 1-2 秒）
sleep 2

# 查看計算結果
curl http://<url>/api/values/current
# 應該看到 "7": "21"
```

- [ ] 計算功能正常
- [ ] PostgreSQL 儲存索引正常
- [ ] Redis pub/sub 正常
- [ ] Worker 計算正常

### 監控設置（選用）

- [ ] CloudWatch Logs 查看應用日誌
- [ ] 設定 CloudWatch Alarms（CPU、Memory、Health）
- [ ] 設定 SNS 通知

---

## 📋 Production 環境部署

### 前置準備

- [ ] Staging 環境已穩定運行至少 1 週
- [ ] 所有功能測試通過
- [ ] 效能測試完成
- [ ] 安全掃描完成
- [ ] 準備好回滾計劃

### AWS 基礎設施建立（約 20 分鐘）

- [ ] 執行 `./scripts/setup-aws-infrastructure.sh` 選擇 Production
- [ ] 使用**強式密碼**（建議使用密碼管理器產生）
- [ ] 確認 Multi-AZ 啟用（高可用性）
- [ ] 確認備份保留期為 14 天
- [ ] 記錄所有 endpoints 和 credentials

### Elastic Beanstalk 環境建立（約 5 分鐘）

- [ ] Create new environment
  - [ ] Environment name: `fib-app-production`
  - [ ] Instance type: `t3.small` 或更高
  - [ ] Auto Scaling: Min 2, Max 4 instances
  - [ ] Rolling updates: 25% batch size
- [ ] 啟用 HTTPS（建議使用 ACM certificate）
- [ ] 設定 custom domain（選用）

### GitHub Secrets 設定

- [ ] `PRODUCTION_RDS_ENDPOINT`
- [ ] `PRODUCTION_REDIS_ENDPOINT`
- [ ] `PRODUCTION_DB_PASSWORD`

### 部署執行

- [ ] **重要：** 確認沒有未測試的程式碼
- [ ] 推送至 main 分支或建立 version tag
- [ ] 如使用 workflow_dispatch，輸入 "DEPLOY" 確認
- [ ] 監控部署過程
- [ ] 等待 health check 通過

### Production 驗證

- [ ] Health check 通過
- [ ] 功能測試通過
- [ ] 效能符合預期
- [ ] 錯誤率正常
- [ ] 監控 CloudWatch metrics 10 分鐘

### Production 上線後

- [ ] 更新 DNS 指向 production URL（如使用 custom domain）
- [ ] 設定 CloudWatch Alarms
- [ ] 設定 on-call rotation
- [ ] 更新 runbook 文件
- [ ] 通知相關人員上線完成

---

## 🔥 緊急回滾程序

如果 Production 部署出現問題：

```bash
# 1. 立即回滾至前一版本
aws elasticbeanstalk update-environment \
  --environment-name fib-app-production \
  --version-label <previous-version-label> \
  --region ap-northeast-1

# 2. 驗證回滾成功
curl http://<production-url>/api/health

# 3. 通知團隊
# 4. 調查問題
# 5. 修復後重新部署
```

---

## 📊 成本追蹤

### Staging 環境（每月）
- EC2: ~$18
- RDS: ~$18
- ElastiCache: ~$14
- ALB: ~$22
- **總計: ~$77**

### Production 環境（每月）
- EC2 (2-4 instances): ~$36-72
- RDS Multi-AZ: ~$36
- ElastiCache Multi-AZ: ~$28
- ALB: ~$22
- **總計: ~$122-158**

### 節省成本建議
- [ ] 使用 Savings Plans
- [ ] 非工作時間停止 Staging 環境
- [ ] 啟用 Cost Explorer
- [ ] 設定 Budgets Alerts

---

## ✅ 完成狀態

- [ ] Staging 環境部署完成
- [ ] Production 環境部署完成
- [ ] 監控與告警設置完成
- [ ] 文件更新完成
- [ ] 團隊培訓完成
