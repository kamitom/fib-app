# 部署指南

## 概述

本指南說明如何將 Fibonacci 多容器應用程式部署至 AWS Elastic Beanstalk。

## 前置條件

部署前，請確認已完成**選項 B**（穩健 CD 準備）：

✅ Health check endpoints ([fib-be/main.py:130](../fib-be/main.py#L130), [fib-worker/index.js:20](../fib-worker/index.js#L20))
✅ Integration tests ([tests/test_integration.py](../tests/test_integration.py))
✅ Database schema 文件 ([DATABASE.md](./DATABASE.md))
✅ Environment 配置檔案 (`.env.staging.example`, `.env.production.example`)

## 部署策略：AWS Elastic Beanstalk

### 為什麼選擇 Elastic Beanstalk？

- **原生 multi-container 支援** - 透過 `Dockerrun.aws.json`
- **零架構改動** - 直接使用現有 docker-compose 設定
- **託管基礎設施** - 自動擴展、負載平衡、健康檢查
- **RDS & ElastiCache 整合** - 託管 PostgreSQL 和 Redis

### 架構圖

```
┌─────────────────────────────────────────────┐
│ Application Load Balancer (ALB)             │
└─────────────────┬───────────────────────────┘
                  │
    ┌─────────────┼─────────────┐
    │             │             │
┌───▼────┐   ┌───▼────┐   ┌───▼────┐
│ EC2-1  │   │ EC2-2  │   │ EC2-3  │
│        │   │        │   │        │
│ nginx  │   │ nginx  │   │ nginx  │
│ client │   │ client │   │ client │
│ api    │   │ api    │   │ api    │
│ worker │   │ worker │   │ worker │
└────────┘   └────────┘   └────────┘
     │            │            │
     └────────┬───┴────────────┘
              │
    ┌─────────┼─────────────┐
    │                       │
┌───▼──────────┐   ┌────────▼─────┐
│ RDS          │   │ ElastiCache  │
│ PostgreSQL   │   │ Redis        │
└──────────────┘   └──────────────┘
```

## 基礎設施設置

### 1. 建立 RDS PostgreSQL 資料庫

```bash
# AWS Console: RDS > 建立資料庫
引擎：PostgreSQL 17
範本：開發/測試 (staging) 或 正式環境 (production)
執行個體類別：db.t3.micro (staging) 或 db.t3.small (production)
儲存空間：20 GB SSD
多可用區域：否 (staging) / 是 (production)
資料庫名稱：fib_staging / fib_production
主使用者名稱：fib_staging / fib_prod
主密碼：<強式密碼>

# 啟用自動備份
備份保留期：7 天
```

**取得 RDS Endpoint：**
```bash
aws rds describe-db-instances \
  --db-instance-identifier fib-staging \
  --region ap-northeast-1 \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text
```

### 2. 建立 ElastiCache Redis 叢集

```bash
# AWS Console: ElastiCache > 建立 Redis 叢集
引擎：Redis 7.x
節點類型：cache.t3.micro (staging) 或 cache.t3.small (production)
複本數量：0 (staging) / 2 (production)
多可用區域：否 (staging) / 是 (production)

# 啟用自動備份（僅 production）
快照保留期：5 天
```

**取得 Redis Endpoint：**
```bash
aws elasticache describe-cache-clusters \
  --cache-cluster-id fib-staging-redis \
  --region ap-northeast-1 \
  --show-cache-node-info \
  --query 'CacheClusters[0].CacheNodes[0].Endpoint.Address' \
  --output text
```

### 3. 建立 Elastic Container Registry (ECR)

```bash
# 建立 4 個 ECR repositories
aws ecr create-repository --repository-name fib-fe --region ap-northeast-1
aws ecr create-repository --repository-name fib-be --region ap-northeast-1
aws ecr create-repository --repository-name fib-worker --region ap-northeast-1
aws ecr create-repository --repository-name fib-nginx --region ap-northeast-1

# 取得登入指令
aws ecr get-login-password --region ap-northeast-1 | \
  docker login --username AWS --password-stdin <account-id>.dkr.ecr.ap-northeast-1.amazonaws.com
```

### 4. 設定 GitHub Secrets

前往 repository Settings > Secrets and variables > Actions 新增：

```
AWS_ACCESS_KEY_ID=<IAM_使用者金鑰>
AWS_SECRET_ACCESS_KEY=<IAM_使用者密鑰>
AWS_REGION=ap-northeast-1
ECR_REGISTRY=<account-id>.dkr.ecr.ap-northeast-1.amazonaws.com

# Staging 環境
STAGING_RDS_ENDPOINT=<rds-endpoint>
STAGING_REDIS_ENDPOINT=<redis-endpoint>
STAGING_DB_PASSWORD=<密碼>

# Production 環境
PRODUCTION_RDS_ENDPOINT=<rds-endpoint>
PRODUCTION_REDIS_ENDPOINT=<redis-endpoint>
PRODUCTION_DB_PASSWORD=<密碼>
```

## Dockerrun.aws.json 配置

為 Elastic Beanstalk multi-container 部署建立 `Dockerrun.aws.json`：

```json
{
  "AWSEBDockerrunVersion": 2,
  "containerDefinitions": [
    {
      "name": "nginx",
      "image": "<ECR_REGISTRY>/fib-nginx:latest",
      "memory": 128,
      "essential": true,
      "portMappings": [
        {
          "hostPort": 80,
          "containerPort": 80
        }
      ],
      "links": ["client", "api"]
    },
    {
      "name": "client",
      "image": "<ECR_REGISTRY>/fib-fe:latest",
      "memory": 256,
      "essential": true
    },
    {
      "name": "api",
      "image": "<ECR_REGISTRY>/fib-be:latest",
      "memory": 512,
      "essential": true,
      "environment": [
        {"name": "REDIS_HOST", "value": "$REDIS_HOST"},
        {"name": "PGHOST", "value": "$PGHOST"},
        {"name": "PGUSER", "value": "$PGUSER"},
        {"name": "PGDATABASE", "value": "$PGDATABASE"},
        {"name": "PGPASSWORD", "value": "$PGPASSWORD"}
      ]
    },
    {
      "name": "worker",
      "image": "<ECR_REGISTRY>/fib-worker:latest",
      "memory": 256,
      "essential": false,
      "environment": [
        {"name": "REDIS_HOST", "value": "$REDIS_HOST"}
      ]
    }
  ]
}
```

## GitHub Actions CD Workflow

建立 `.github/workflows/deploy-staging.yml`：

```yaml
name: Deploy to Staging

on:
  push:
    branches: [develop]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ secrets.AWS_REGION }}

      - name: Login to ECR
        run: |
          aws ecr get-login-password --region ${{ secrets.AWS_REGION }} | \
          docker login --username AWS --password-stdin ${{ secrets.ECR_REGISTRY }}

      - name: Build and push images
        run: |
          docker build -t ${{ secrets.ECR_REGISTRY }}/fib-fe:${{ github.sha }} ./fib-fe
          docker build -t ${{ secrets.ECR_REGISTRY }}/fib-be:${{ github.sha }} ./fib-be
          docker build -t ${{ secrets.ECR_REGISTRY }}/fib-worker:${{ github.sha }} ./fib-worker
          docker build -t ${{ secrets.ECR_REGISTRY }}/fib-nginx:${{ github.sha }} ./nginx

          docker push ${{ secrets.ECR_REGISTRY }}/fib-fe:${{ github.sha }}
          docker push ${{ secrets.ECR_REGISTRY }}/fib-be:${{ github.sha }}
          docker push ${{ secrets.ECR_REGISTRY }}/fib-worker:${{ github.sha }}
          docker push ${{ secrets.ECR_REGISTRY }}/fib-nginx:${{ github.sha }}

      - name: Deploy to Elastic Beanstalk
        run: |
          # 使用 image tags 產生 Dockerrun.aws.json
          # 部署至 EB 環境
          eb deploy fib-staging --staged
```

## 健康檢查

Elastic Beanstalk 健康檢查設定：

```
目標：HTTP:80/api/health
健康門檻：2
不健康門檻：5
逾時：5 秒
間隔：30 秒
```

預期回應：
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

## 監控

- **CloudWatch Logs**：所有容器的應用程式日誌
- **CloudWatch Metrics**：CPU、記憶體、請求數、延遲
- **X-Ray**：分散式追蹤（選用）
- **RDS Metrics**：資料庫連線、IOPS、儲存空間
- **ElastiCache Metrics**：快取命中率、逐出、連線數

## 回滾

```bash
# 列出部署版本
eb appversion lifecycle -v

# 回滾至先前版本
eb deploy fib-staging --version <version-label>
```

## 成本估算（Staging 環境 - 東京區域）

- **EC2 (t3.small)**：約 $18/月
- **RDS (db.t3.micro)**：約 $18/月
- **ElastiCache (cache.t3.micro)**：約 $14/月
- **ALB**：約 $22/月
- **資料傳輸**：約 $5/月
- **總計**：約 **$77/月**

*註：東京區域價格較美東略高約 15%*

## 下一步

1. ✅ 完成選項 B 準備（本文件假設已完成）
2. ⬜ 建立 Dockerrun.aws.json 範本
3. ⬜ 設置 AWS 基礎設施（RDS、ElastiCache、ECR）
4. ⬜ 設定 GitHub Secrets
5. ⬜ 建立 deploy-staging.yml workflow
6. ⬜ 測試 staging 環境部署
7. ⬜ 建立 deploy-production.yml workflow
8. ⬜ 設置監控與告警
