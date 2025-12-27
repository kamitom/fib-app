# AWS Infrastructure Scripts

AWS 基礎設施自動化腳本集，用於快速建立和清理 Fib-App 所需的 AWS 資源。

## 📋 腳本列表

| 腳本 | 用途 | 日誌記錄 |
|------|------|---------|
| `setup-aws-infrastructure.sh` | 建立 AWS 基礎設施 | ❌ 不記錄 |
| `setup-aws-infrastructure-with-logging.sh` | 建立 AWS 基礎設施 | ✅ 記錄並脫敏 |
| `cleanup-aws-infrastructure.sh` | 清理 AWS 資源 | ❌ 不記錄 |
| `cleanup-aws-infrastructure-with-logging.sh` | 清理 AWS 資源 | ✅ 記錄並脫敏 |
| `verify-aws-infrastructure.sh` | 驗證資源建立成功 | ❌ 不記錄 |
| `check-remaining-resources.sh` | 檢查 cleanup 後殘留資源 | ❌ 不記錄 |
| `create-iam-user.sh` | 建立 IAM 使用者（用於 GitHub Actions） | N/A |

## 🚀 快速開始

### 1. 建立基礎設施

**不記錄日誌（快速測試）**：
```bash
./scripts/setup-aws-infrastructure.sh
```

**記錄日誌（正式部署）**：
```bash
./scripts/setup-aws-infrastructure-with-logging.sh
```

執行後會：
- ✅ 建立 RDS PostgreSQL 17
- ✅ 建立 ElastiCache Redis 7
- ✅ 建立 4 個 ECR repositories
- ✅ 建立 Elastic Beanstalk Application
- ✅ 建立 Elastic Beanstalk Environment
- ✅ 配置 Security Groups
- ✅ 建立 S3 bucket

**執行時間**: 約 20-25 分鐘

### 2. 清理資源

**不記錄日誌**：
```bash
./scripts/cleanup-aws-infrastructure.sh
```

**記錄日誌（推薦）**：
```bash
./scripts/cleanup-aws-infrastructure-with-logging.sh
```

**執行時間**: 約 10-15 分鐘

### 3. 驗證資源

**建立後驗證**：
```bash
./scripts/verify-aws-infrastructure.sh
# 互動式選擇環境（Staging 或 Production）
# 驗證 10 個檢查項目
```

**清理後檢查**：
```bash
./scripts/check-remaining-resources.sh staging
# 或
./scripts/check-remaining-resources.sh production
```

## ⚠️ 重要說明

### 日誌記錄版本 vs 非日誌版本

#### 為什麼有兩個版本？

Bash 的互動式輸入（`read` 命令）與自動 I/O 重定向不相容。因此提供兩個版本：

- **非日誌版本** (`*.sh`)：直接執行，互動式輸入正常，不記錄日誌
- **日誌版本** (`*-with-logging.sh`)：使用 wrapper，記錄並自動脫敏日誌

#### 選擇建議

- **測試/學習**: 使用非日誌版本（快速）
- **正式部署**: 使用日誌版本（可審計）
- **問題排查**: 使用日誌版本（有完整記錄）

### 日誌安全性

日誌版本會自動脫敏以下資訊：
- ✅ 資料庫密碼
- ✅ AWS Access Keys (AKIA...)
- ✅ AWS Secret Keys (40 字元)
- ✅ AWS Account ID

## 📖 詳細文件

- [日誌系統說明](./README-LOGS.md) - 日誌記錄、脫敏、查看方法
- [CD 快速啟動](../docs/QUICK-START-CD.md) - 完整 CD 流程
- [完整部署指南](../docs/DEPLOYMENT.md) - 詳細部署文件

## 💡 使用範例

### 範例 1：測試流程（不保留資源）

```bash
# 1. 建立資源（不記錄）
./scripts/setup-aws-infrastructure.sh
# 選擇 Staging
# 輸入資料庫配置
# 等待 20 分鐘

# 2. 驗證資源
./scripts/verify-aws-infrastructure.sh
# 選擇 1) Staging
# 檢查 10 個項目

# 3. 清理資源（避免費用）
./scripts/cleanup-aws-infrastructure.sh
# 選擇 Staging
# 確認刪除

# 4. 確認清理完成
./scripts/check-remaining-resources.sh staging
```

### 範例 2：正式部署（保留完整日誌）

```bash
# 1. 建立資源（記錄日誌）
./scripts/setup-aws-infrastructure-with-logging.sh
# 選擇 Staging
# 輸入資料庫配置
# 等待完成

# 2. 驗證所有資源
./scripts/verify-aws-infrastructure.sh
# 選擇 1) Staging
# 確認所有 10 項檢查通過

# 3. 檢查日誌
ls -lt logs/setup-*.log | head -1
cat $(ls -t logs/setup-*.log | head -1)

# 4. 記下 endpoints（用於 GitHub Secrets）
grep "Endpoint" $(ls -t logs/setup-*.log | head -1)

# 5. 設定 GitHub Secrets
# （複製腳本輸出的值）

# 6. 部署應用
git checkout -b develop
git push -u origin develop
```

## 🛠️ 前置需求

### AWS CLI

```bash
# 安裝
pip install awscli

# 設定
aws configure
# AWS Access Key ID: <your-key>
# AWS Secret Access Key: <your-secret>
# Default region: ap-northeast-1
# Default output format: json
```

### 權限需求

IAM 使用者需要以下權限：
- RDS (建立/刪除資料庫)
- ElastiCache (建立/刪除 Redis)
- ECR (建立/刪除 repositories)
- Elastic Beanstalk (建立/刪除 application & environment)
- EC2 (Security Groups, VPC)
- S3 (建立/刪除 bucket)
- IAM (讀取帳號資訊)

**建議**: 使用 `AdministratorAccess` 或建立自訂 policy

## 📊 成本估算

### Staging 環境（ap-northeast-1）

| 資源 | 規格 | 月費用（USD） |
|------|------|-------------|
| RDS PostgreSQL | db.t3.micro | ~$18 |
| ElastiCache Redis | cache.t3.micro | ~$14 |
| Elastic Beanstalk | t3.small | ~$18 |
| Application Load Balancer | - | ~$22 |
| **總計** | | **~$77/月** |

### 節省成本建議

1. **使用 AWS Free Tier** (新帳號首 12 個月)
2. **非工作時間停止 Staging**:
   ```bash
   aws elasticbeanstalk update-environment \
     --environment-name fib-app-staging \
     --option-settings Namespace=aws:autoscaling:asg,OptionName=MinSize,Value=0
   ```
3. **測試完立即清理**（使用 cleanup 腳本）

## 🔍 故障排除

### 問題 1: 腳本執行時無法輸入

**症狀**: 執行 `setup-aws-infrastructure.sh` 時，`read` 提示無回應

**原因**: 使用了舊版腳本（含自動 I/O 重定向）

**解決**:
```bash
# 方案 1: 使用日誌版本
./scripts/setup-aws-infrastructure-with-logging.sh

# 方案 2: 確保腳本是最新版（無 exec 重定向）
grep "exec > >" scripts/setup-aws-infrastructure.sh
# 應該沒有輸出
```

### 問題 2: RDS 建立失敗

**可能原因**:
- ✗ 密碼不符合要求（至少 8 字元）
- ✗ Security Group 已存在但有衝突規則
- ✗ 達到 RDS 資源限制

**檢查**:
```bash
aws rds describe-db-instances \
  --db-instance-identifier fib-app-staging-db \
  --region ap-northeast-1
```

### 問題 3: EB Environment 建立超時

**可能原因**:
- ✗ IAM Role `aws-elasticbeanstalk-ec2-role` 不存在
- ✗ Subnets 配置問題

**解決**: 手動建立 IAM Role 或使用 EB CLI 初始化

## 📞 支援

遇到問題？請檢查：
1. [日誌文件](./README-LOGS.md) - 查看日誌排錯
2. [GitHub Issues](https://github.com/your-repo/issues)
3. AWS CloudWatch Logs - EB 環境日誌
