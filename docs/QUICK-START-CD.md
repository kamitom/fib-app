# CD 快速啟動指南

完整版請參考 [DEPLOYMENT.md](./DEPLOYMENT.md)

## 🚀 30 分鐘完成 Staging 部署

### 前置準備

1. **AWS CLI 安裝與設定**
```bash
# 安裝 AWS CLI
pip install awscli

# 設定 credentials
aws configure
# AWS Access Key ID: <your-key>
# AWS Secret Access Key: <your-secret>
# Default region: ap-northeast-1
# Default output format: json
```

2. **確認權限**

需要以下 AWS 服務權限：
- RDS (建立資料庫)
- ElastiCache (建立 Redis)
- ECR (建立 registry)
- Elastic Beanstalk (建立應用)
- S3 (存放部署包)
- EC2/VPC (網路與安全群組)

### 步驟 1: 建立 AWS 基礎設施（20 分鐘）

```bash
# 執行自動化腳本
./scripts/setup-aws-infrastructure.sh

# 選擇環境
# 1) Staging
# 2) Production
選擇: 1

# 輸入資料庫配置
PostgreSQL 主使用者名稱: fib_staging
PostgreSQL 主密碼: <輸入強式密碼>
```

腳本會自動建立：
- ✅ RDS PostgreSQL 17 (db.t3.micro)
- ✅ ElastiCache Redis 7 (cache.t3.micro)
- ✅ 4 個 ECR repositories (fib-fe, fib-be, fib-worker, fib-nginx)
- ✅ S3 bucket for deployments
- ✅ Security groups

**預計時間：15-20 分鐘**

### 步驟 2: 建立 Elastic Beanstalk 環境（5 分鐘）

前往 AWS Console > Elastic Beanstalk > Create environment

```
Application name: fib-app
Environment name: fib-app-staging
Platform: Docker
Platform branch: Multi-container Docker
Environment type: Load balanced
EC2 instance type: t3.small

Network:
- VPC: (選擇 default VPC)
- Public subnets: (選擇至少 2 個)

Security:
- EC2 security group: fib-app-staging-eb-sg

Monitoring:
- Health reporting: Enhanced
- Managed updates: Enabled
```

點擊 **Create environment**

### 步驟 3: 設定 GitHub Secrets（2 分鐘）

前往 GitHub repository > Settings > Secrets and variables > Actions

新增以下 secrets（從 setup 腳本輸出複製）：

```
AWS_ACCESS_KEY_ID=<your-iam-key>
AWS_SECRET_ACCESS_KEY=<your-iam-secret>
AWS_ACCOUNT_ID=<12-digit-account-id>
AWS_REGION=ap-northeast-1
ECR_REGISTRY=<account-id>.dkr.ecr.ap-northeast-1.amazonaws.com

STAGING_RDS_ENDPOINT=<rds-endpoint-from-script>
STAGING_REDIS_ENDPOINT=<redis-endpoint-from-script>
STAGING_DB_PASSWORD=<your-db-password>
```

### 步驟 4: 建立 develop 分支並部署（3 分鐘）

```bash
# 建立 develop 分支
git checkout -b develop
git push -u origin develop

# 觸發部署
git commit --allow-empty -m "trigger staging deployment"
git push origin develop
```

前往 GitHub Actions 查看部署進度。

### 步驟 5: 驗證部署（1 分鐘）

部署完成後，取得環境 URL：

```bash
aws elasticbeanstalk describe-environments \
  --application-name fib-app \
  --environment-names fib-app-staging \
  --region ap-northeast-1 \
  --query 'Environments[0].CNAME' \
  --output text
```

測試 health check：

```bash
curl http://<environment-url>/api/health
```

預期輸出：
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

訪問應用：`http://<environment-url>`

## ✅ 完成！

你的 Staging 環境已經運行。

## 下一步

### 測試應用功能

```bash
# 提交 Fibonacci 計算
curl -X POST http://<environment-url>/api/values \
  -H "Content-Type: application/json" \
  -d '{"index": 10}'

# 查看所有索引
curl http://<environment-url>/api/values/all

# 查看計算結果
curl http://<environment-url>/api/values/current
```

### 設置 Production 環境

1. 再次執行 `./scripts/setup-aws-infrastructure.sh` 選擇 Production
2. 建立 Elastic Beanstalk production 環境
3. 設定 GitHub Secrets (PRODUCTION_*)
4. 推送至 main 分支部署

### 監控與維護

```bash
# 查看應用日誌
eb logs fib-app-staging

# 查看環境狀態
aws elasticbeanstalk describe-environment-health \
  --environment-name fib-app-staging \
  --attribute-names All \
  --region ap-northeast-1

# 回滾部署
aws elasticbeanstalk update-environment \
  --environment-name fib-app-staging \
  --version-label <previous-version> \
  --region ap-northeast-1
```

## 常見問題

**Q: 部署失敗怎麼辦？**

檢查 GitHub Actions logs 和 EB environment health：
```bash
aws elasticbeanstalk describe-events \
  --environment-name fib-app-staging \
  --region ap-northeast-1 \
  --max-items 20
```

**Q: 如何節省成本？**

Staging 環境可在非工作時間關閉：
```bash
# 停止環境（保留配置）
aws elasticbeanstalk update-environment \
  --environment-name fib-app-staging \
  --option-settings Namespace=aws:autoscaling:asg,OptionName=MinSize,Value=0 \
  --region ap-northeast-1
```

**Q: 如何更新環境變數？**

修改 GitHub Secrets 後重新部署即可。

## 成本估算

**Staging 環境（東京區域）：**
- EC2 (t3.small): $18/月
- RDS (db.t3.micro): $18/月
- ElastiCache (cache.t3.micro): $14/月
- ALB: $22/月
- **總計: ~$77/月**

**節省建議：**
- 使用 AWS Free Tier（新帳號首 12 個月）
- 非工作時間停止 staging 環境
- 使用 Savings Plans 或 Reserved Instances
