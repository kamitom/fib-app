# Elastic Beanstalk ECS 部署問題診斷與修復總結

## 時間線
2025-12-28 - 首次 Staging 部署測試

## 遇到的問題與解決方案

### 1. Frontend Nginx 配置語法錯誤
**症狀**: Health check 返回 404
**根本原因**: `fib-fe/nginx/default.conf` 缺少 `server` 關鍵字
**修復**:
```nginx
# 錯誤
{
  listen 5173;
  ...
}

# 正確
server {
  listen 5173;
  ...
}
```

### 2. S3 Bucket ACL 權限問題
**症狀**:
- EB 事件日誌: "Service:Amazon S3, Message:The bucket does not allow ACLs"
- Application versions 狀態: UNPROCESSED
- 部署失敗

**根本原因**:
- EB 自動創建的 S3 bucket 默認設定 `ObjectOwnership: BucketOwnerEnforced`
- 這個設定禁用了 ACL
- EB 部署時嘗試使用 ACL 上傳檔案，導致失敗

**修復**:
```bash
aws s3api put-bucket-ownership-controls \
  --bucket elasticbeanstalk-ap-northeast-1-950555671003 \
  --ownership-controls 'Rules=[{ObjectOwnership=ObjectWriter}]'
```

**預防**: 在 setup script 中加入自動修復邏輯

### 3. IAM ECR 權限缺失
**症狀**:
- ECS task 無法啟動
- 錯誤: "User is not authorized to perform: ecr:GetAuthorizationToken"
- 所有容器狀態: CannotPullECRContainerError

**根本原因**:
- `AWSElasticBeanstalkMulticontainerDocker` managed policy 不包含 ECR 權限
- 該策略是為舊的 Multi-container Docker platform 設計
- ECS platform 需要從 ECR pull images，但沒有必要的權限

**需要的 ECR 權限**:
- `ecr:GetAuthorizationToken` - 獲取 ECR 登入 token
- `ecr:BatchCheckLayerAvailability` - 檢查 image layers
- `ecr:GetDownloadUrlForLayer` - 下載 layers
- `ecr:BatchGetImage` - 拉取 images

**修復**: 創建 inline policy
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage"
      ],
      "Resource": "*"
    }
  ]
}
```

### 4. 未解決：容器立即退出
**症狀**:
- ECS task 啟動成功但所有容器 STOPPED
- StopCode: EssentialContainerExited
- 502 Bad Gateway

**可能原因**:
1. 應用啟動失敗（frontend/backend 內部錯誤）
2. 環境變數配置錯誤
3. 容器依賴問題（數據庫連接失敗等）

**需要進一步診斷**:
- 查看 CloudWatch Logs
- 檢查容器啟動日誌
- 驗證環境變數是否正確傳遞
- 測試容器本地是否能正常運行

## 已修復的文件

1. `fib-fe/nginx/default.conf` - Frontend nginx 配置
2. `nginx/default.conf` - 主 nginx 反向代理配置
3. `scripts/setup-aws-infrastructure.sh` - 加入 S3 ACL 和 ECR 權限修復
4. `.github/workflows/deploy-staging.yml` - 加入 debug 日誌

## 學到的經驗

### EB ECS Platform 特殊要求
1. **必須使用 ECS running on AL2023 platform** - Multi-container Docker 已棄用
2. **需要額外的 ECR 權限** - Managed policies 不足夠
3. **S3 bucket 需要允許 ACL** - 新 buckets 默認禁用

### 架構理解
- EB ALB → ECS Task → Nginx Container → Client/API Containers
- 所有容器在同一個 task 中，通過 Docker links 通信
- Nginx 作為反向代理路由請求

### IAM 權限陷阱
- AWS Managed Policies 可能過時或不完整
- ECS + ECR 組合需要明確的 GetAuthorizationToken 權限
- Instance Profile 需要 inline policy 補充權限

## 下一步建議

1. **診斷容器退出問題**
   - 啟用 CloudWatch Logs
   - 檢查應用啟動腳本
   - 驗證環境變數

2. **簡化部署測試**
   - 先測試單個容器（只部署 backend）
   - 確認數據庫/Redis 連接
   - 逐步加入其他容器

3. **改進監控**
   - 設定 CloudWatch Log Groups
   - 加入健康檢查端點
   - 配置 EB 環境變數可見性
