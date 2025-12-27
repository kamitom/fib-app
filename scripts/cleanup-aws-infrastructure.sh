#!/bin/bash
# 清理 AWS 基礎設施腳本
# 用途：刪除由 setup-aws-infrastructure.sh 建立的所有資源
# 警告：此操作不可逆！請確認後再執行

set -e

# Disable AWS CLI pager to prevent interactive prompts
export AWS_PAGER=""

REGION="ap-northeast-1"


# 顏色輸出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${RED}================================================${NC}"
echo -e "${RED}  AWS 基礎設施清理腳本${NC}"
echo -e "${RED}  警告：此操作將刪除所有資源且無法復原！${NC}"
echo -e "${RED}================================================${NC}"
echo ""

# 選擇環境
echo "請選擇要清理的環境："
echo "1) Staging"
echo "2) Production"
echo "3) 全部清理（Staging + Production）"
read -p "請選擇 [1-3]: " ENV_CHOICE

case $ENV_CHOICE in
  1)
    ENVIRONMENTS=("staging")
    ;;
  2)
    ENVIRONMENTS=("production")
    ;;
  3)
    ENVIRONMENTS=("staging" "production")
    ;;
  *)
    echo -e "${RED}無效選擇${NC}"
    exit 1
    ;;
esac

# Dry-run 模式
echo ""
read -p "是否先執行 dry-run 預覽將被刪除的資源？(y/n): " -n 1 -r
echo
DRY_RUN=false
if [[ $REPLY =~ ^[Yy]$ ]]; then
  DRY_RUN=true
  echo -e "${YELLOW}=== DRY-RUN 模式 ===${NC}"
fi

# 取得 AWS Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
if [ -z "$ACCOUNT_ID" ]; then
  echo -e "${RED}錯誤：無法取得 AWS Account ID，請確認 AWS CLI 已設定${NC}"
  exit 1
fi

echo ""
echo "AWS Account ID: $ACCOUNT_ID"
echo "AWS Region: $REGION"
echo "將清理環境: ${ENVIRONMENTS[@]}"
echo ""

# 函數：檢查資源是否存在
check_rds_exists() {
  local db_id=$1
  aws rds describe-db-instances --db-instance-identifier $db_id --region $REGION &>/dev/null
  return $?
}

check_elasticache_exists() {
  local cache_id=$1
  aws elasticache describe-cache-clusters --cache-cluster-id $cache_id --region $REGION &>/dev/null
  return $?
}

check_ecr_exists() {
  local repo_name=$1
  aws ecr describe-repositories --repository-names $repo_name --region $REGION &>/dev/null
  return $?
}

check_sg_exists() {
  local sg_name=$1
  aws ec2 describe-security-groups --filters "Name=group-name,Values=$sg_name" --region $REGION --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null | grep -v "None"
  return $?
}

# 函數：刪除 RDS 實例
delete_rds() {
  local env=$1
  local db_id="fib-app-${env}-db"

  echo -e "${YELLOW}檢查 RDS 實例: $db_id${NC}"

  if check_rds_exists $db_id; then
    echo -e "  ✓ 找到 RDS 實例"

    if [ "$DRY_RUN" = true ]; then
      echo -e "  ${YELLOW}[DRY-RUN] 將刪除 RDS: $db_id${NC}"
    else
      echo -e "  ${RED}刪除 RDS 實例（不建立最終快照）...${NC}"
      aws rds delete-db-instance \
        --db-instance-identifier $db_id \
        --skip-final-snapshot \
        --region $REGION
      echo -e "  ${GREEN}✓ RDS 刪除已啟動（約需 5-10 分鐘）${NC}"
    fi
  else
    echo -e "  ⊘ RDS 實例不存在，跳過"
  fi
}

# 函數：刪除 ElastiCache
delete_elasticache() {
  local env=$1
  local cache_id="fib-app-${env}-redis"

  echo -e "${YELLOW}檢查 ElastiCache: $cache_id${NC}"

  if check_elasticache_exists $cache_id; then
    echo -e "  ✓ 找到 ElastiCache cluster"

    if [ "$DRY_RUN" = true ]; then
      echo -e "  ${YELLOW}[DRY-RUN] 將刪除 ElastiCache: $cache_id${NC}"
    else
      echo -e "  ${RED}刪除 ElastiCache cluster...${NC}"
      aws elasticache delete-cache-cluster \
        --cache-cluster-id $cache_id \
        --region $REGION
      echo -e "  ${GREEN}✓ ElastiCache 刪除已啟動（約需 2-5 分鐘）${NC}"
    fi
  else
    echo -e "  ⊘ ElastiCache cluster 不存在，跳過"
  fi
}

# 函數：刪除 Security Groups
delete_security_groups() {
  local env=$1

  echo -e "${YELLOW}檢查 Security Groups (${env})${NC}"

  local sg_names=(
    "fib-app-${env}-rds-sg"
    "fib-app-${env}-redis-sg"
    "fib-app-${env}-eb-sg"
  )

  # 需要等待 RDS 和 ElastiCache 完全刪除後才能刪除 SG
  for sg_name in "${sg_names[@]}"; do
    local sg_id=$(check_sg_exists $sg_name)
    if [ -n "$sg_id" ] && [ "$sg_id" != "None" ]; then
      echo -e "  ✓ 找到 Security Group: $sg_name ($sg_id)"

      if [ "$DRY_RUN" = true ]; then
        echo -e "  ${YELLOW}[DRY-RUN] 將刪除 SG: $sg_name${NC}"
      else
        echo -e "  ${YELLOW}⚠ Security Group 將稍後刪除（需等待 RDS/Redis 完全移除）${NC}"
        # 不在此處刪除，記錄下來稍後處理
        echo "$sg_id" >> /tmp/fib-app-sg-to-delete.txt
      fi
    else
      echo -e "  ⊘ Security Group $sg_name 不存在，跳過"
    fi
  done
}

# 函數：刪除 ECR repositories
delete_ecr_repositories() {
  echo -e "${YELLOW}檢查 ECR Repositories${NC}"

  local repos=("fib-fe" "fib-be" "fib-worker" "fib-nginx")

  for repo in "${repos[@]}"; do
    if check_ecr_exists $repo; then
      echo -e "  ✓ 找到 ECR repository: $repo"

      if [ "$DRY_RUN" = true ]; then
        echo -e "  ${YELLOW}[DRY-RUN] 將刪除 ECR repository: $repo${NC}"
      else
        echo -e "  ${RED}刪除 ECR repository（包含所有映像檔）...${NC}"
        aws ecr delete-repository \
          --repository-name $repo \
          --region $REGION \
          --force
        echo -e "  ${GREEN}✓ ECR repository $repo 已刪除${NC}"
      fi
    else
      echo -e "  ⊘ ECR repository $repo 不存在，跳過"
    fi
  done
}

# 函數：刪除 S3 bucket
delete_s3_bucket() {
  local bucket_name="elasticbeanstalk-${REGION}-${ACCOUNT_ID}"

  echo -e "${YELLOW}檢查 S3 Bucket: $bucket_name${NC}"

  if aws s3 ls "s3://$bucket_name" &>/dev/null; then
    echo -e "  ✓ 找到 S3 bucket"

    if [ "$DRY_RUN" = true ]; then
      echo -e "  ${YELLOW}[DRY-RUN] 將刪除 S3 bucket: $bucket_name${NC}"
      aws s3 ls "s3://$bucket_name" --recursive | head -10
      echo -e "  ${YELLOW}... (顯示前 10 個檔案)${NC}"
    else
      read -p "  警告：將刪除 S3 bucket 及其所有內容，是否繼續？(y/n): " -n 1 -r
      echo
      if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "  ${RED}刪除 S3 bucket 所有內容...${NC}"
        aws s3 rm "s3://$bucket_name" --recursive

        # Remove bucket policy first (EB adds a Deny policy for DeleteBucket)
        echo -e "  ${YELLOW}移除 Bucket Policy（若存在）...${NC}"
        aws s3api delete-bucket-policy --bucket "$bucket_name" --region $REGION 2>/dev/null || true

        echo -e "  ${RED}刪除 S3 bucket...${NC}"
        if aws s3 rb "s3://$bucket_name" --region $REGION 2>/dev/null; then
          echo -e "  ${GREEN}✓ S3 bucket 已刪除${NC}"
        else
          echo -e "  ${YELLOW}⚠ S3 bucket 刪除失敗${NC}"
          echo -e "  ${YELLOW}  請手動前往 AWS Console 確認${NC}"
        fi
      else
        echo -e "  ${YELLOW}⊘ 跳過 S3 bucket 刪除${NC}"
      fi
    fi
  else
    echo -e "  ⊘ S3 bucket 不存在，跳過"
  fi
}

# 函數：刪除 Elastic Beanstalk environments
delete_eb_environments() {
  local env=$1
  local app_name="fib-app"
  local env_name="${app_name}-${env}"

  echo -e "${YELLOW}檢查 Elastic Beanstalk Environment: $env_name${NC}"

  local env_exists=$(aws elasticbeanstalk describe-environments \
    --application-name $app_name \
    --environment-names $env_name \
    --region $REGION \
    --query 'Environments[?Status!=`Terminated`].EnvironmentName' \
    --output text 2>/dev/null)

  if [ -n "$env_exists" ]; then
    echo -e "  ✓ 找到 EB environment: $env_name"

    if [ "$DRY_RUN" = true ]; then
      echo -e "  ${YELLOW}[DRY-RUN] 將終止環境: $env_name${NC}"
    else
      echo -e "  ${RED}終止 EB environment...${NC}"
      aws elasticbeanstalk terminate-environment \
        --environment-name $env_name \
        --region $REGION
      echo -e "  ${GREEN}✓ EB environment $env_name 終止已啟動（約需 5-10 分鐘）${NC}"
    fi
  else
    echo -e "  ⊘ EB environment $env_name 不存在，跳過"
  fi
}

# 函數：刪除 Elastic Beanstalk application
delete_eb_application() {
  local app_name="fib-app"

  echo -e "${YELLOW}檢查 Elastic Beanstalk Application: $app_name${NC}"

  local app_exists=$(aws elasticbeanstalk describe-applications \
    --application-names $app_name \
    --region $REGION \
    --query 'Applications[0].ApplicationName' \
    --output text 2>/dev/null)

  if [ -n "$app_exists" ] && [ "$app_exists" != "None" ]; then
    echo -e "  ✓ 找到 EB application"

    # 檢查是否還有運行中的環境
    local remaining_envs=$(aws elasticbeanstalk describe-environments \
      --application-name $app_name \
      --region $REGION \
      --query 'Environments[?Status!=`Terminated`].EnvironmentName' \
      --output text)

    if [ -n "$remaining_envs" ]; then
      echo -e "  ${YELLOW}⚠ 警告：仍有環境在終止中，application 需稍後刪除${NC}"
      echo -e "  ${YELLOW}   請在環境完全終止後重新執行此腳本${NC}"
    else
      if [ "$DRY_RUN" = true ]; then
        echo -e "  ${YELLOW}[DRY-RUN] 將刪除 EB application: $app_name${NC}"
      else
        echo -e "  ${RED}刪除 Elastic Beanstalk application...${NC}"
        aws elasticbeanstalk delete-application \
          --application-name $app_name \
          --region $REGION
        echo -e "  ${GREEN}✓ EB application 已刪除${NC}"
      fi
    fi
  else
    echo -e "  ⊘ EB application 不存在，跳過"
  fi
}

# 函數：刪除 IAM Instance Profile 和 Role
delete_iam_resources() {
  local role_name="aws-elasticbeanstalk-ec2-role"
  local profile_name="aws-elasticbeanstalk-ec2-role"

  echo -e "${YELLOW}檢查 IAM Instance Profile: $profile_name${NC}"

  # Check if instance profile exists
  local profile_exists=$(aws iam get-instance-profile \
    --instance-profile-name $profile_name \
    --query 'InstanceProfile.InstanceProfileName' \
    --output text 2>/dev/null || echo "NOT_FOUND")

  if [ "$profile_exists" != "NOT_FOUND" ]; then
    echo -e "  ✓ 找到 IAM Instance Profile"

    if [ "$DRY_RUN" = true ]; then
      echo -e "  ${YELLOW}[DRY-RUN] 將刪除 IAM Instance Profile 和 Role${NC}"
    else
      echo -e "  ${RED}移除 Role 從 Instance Profile...${NC}"
      aws iam remove-role-from-instance-profile \
        --instance-profile-name $profile_name \
        --role-name $role_name \
        2>/dev/null || true

      echo -e "  ${RED}刪除 Instance Profile...${NC}"
      aws iam delete-instance-profile \
        --instance-profile-name $profile_name \
        2>/dev/null || true

      echo -e "  ${RED}分離 Managed Policies...${NC}"
      aws iam detach-role-policy \
        --role-name $role_name \
        --policy-arn arn:aws:iam::aws:policy/AWSElasticBeanstalkWebTier \
        2>/dev/null || true

      aws iam detach-role-policy \
        --role-name $role_name \
        --policy-arn arn:aws:iam::aws:policy/AWSElasticBeanstalkMulticontainerDocker \
        2>/dev/null || true

      aws iam detach-role-policy \
        --role-name $role_name \
        --policy-arn arn:aws:iam::aws:policy/AWSElasticBeanstalkWorkerTier \
        2>/dev/null || true

      echo -e "  ${RED}刪除 IAM Role...${NC}"
      aws iam delete-role \
        --role-name $role_name \
        2>/dev/null || true

      echo -e "  ${GREEN}✓ IAM 資源已刪除${NC}"
    fi
  else
    echo -e "  ⊘ IAM Instance Profile 不存在，跳過"
  fi
}

# 主程序
echo -e "${RED}================================================${NC}"
echo -e "${RED}  最後確認${NC}"
echo -e "${RED}================================================${NC}"
echo ""
echo "即將清理以下環境的資源: ${ENVIRONMENTS[@]}"
echo ""
echo "將刪除的資源類型："
echo "  - Elastic Beanstalk environments"
echo "  - RDS PostgreSQL 實例"
echo "  - ElastiCache Redis clusters"
echo "  - Security Groups"
echo "  - ECR repositories (含所有映像檔)"
echo "  - S3 bucket (含所有部署檔案)"
echo "  - Elastic Beanstalk application"
echo "  - IAM Instance Profile 和 Role"
echo ""

if [ "$DRY_RUN" = false ]; then
  echo -e "${RED}警告：此操作無法復原！所有資料將永久遺失！${NC}"
  echo ""
  read -p "確認要繼續嗎？請輸入 'DELETE' 以確認: " CONFIRM

  if [ "$CONFIRM" != "DELETE" ]; then
    echo -e "${YELLOW}已取消清理操作${NC}"
    exit 0
  fi
fi

echo ""
echo -e "${GREEN}開始清理...${NC}"
echo ""

# 清理 Security Groups 記錄檔
rm -f /tmp/fib-app-sg-to-delete.txt

# 清理各環境的資源
for env in "${ENVIRONMENTS[@]}"; do
  echo ""
  echo -e "${GREEN}=== 清理 $env 環境 ===${NC}"
  echo ""

  delete_eb_environments $env
  echo ""

  delete_rds $env
  echo ""

  delete_elasticache $env
  echo ""

  delete_security_groups $env
  echo ""
done

# 清理共用資源
echo ""
echo -e "${GREEN}=== 清理共用資源 ===${NC}"
echo ""

delete_ecr_repositories
echo ""

delete_s3_bucket
echo ""

delete_eb_application
echo ""

delete_iam_resources
echo ""

# 清理 Security Groups（需等待）
if [ "$DRY_RUN" = false ] && [ -f /tmp/fib-app-sg-to-delete.txt ]; then
  echo ""
  echo -e "${YELLOW}=== Security Groups 延遲刪除 ===${NC}"
  echo ""
  echo -e "${YELLOW}Security Groups 需要在 RDS 和 ElastiCache 完全刪除後才能移除${NC}"
  echo -e "${YELLOW}請在 10-15 分鐘後執行以下命令手動刪除：${NC}"
  echo ""

  while read sg_id; do
    echo "aws ec2 delete-security-group --group-id $sg_id --region $REGION"
  done < /tmp/fib-app-sg-to-delete.txt

  echo ""
  echo -e "${YELLOW}或重新執行此腳本${NC}"
  rm -f /tmp/fib-app-sg-to-delete.txt
fi

echo ""
echo -e "${GREEN}================================================${NC}"

if [ "$DRY_RUN" = true ]; then
  echo -e "${GREEN}  DRY-RUN 完成${NC}"
  echo -e "${GREEN}================================================${NC}"
  echo ""
  echo "以上是將被刪除的資源清單。"
  echo "如要實際執行刪除，請重新執行腳本並選擇 'n' 跳過 dry-run。"
else
  echo -e "${GREEN}  清理已完成${NC}"
  echo -e "${GREEN}================================================${NC}"
  echo ""
  echo "刪除操作已啟動。部分資源需要數分鐘才會完全移除。"
  echo ""
  echo -e "${YELLOW}預估節省成本：${NC}"

  total_savings=0
  for env in "${ENVIRONMENTS[@]}"; do
    if [ "$env" = "staging" ]; then
      echo "  - Staging 基礎設施: ~$33/月"
      echo "  - Staging EB 環境 (EC2 + ALB): ~$44/月"
      total_savings=$((total_savings + 77))
    else
      echo "  - Production 基礎設施: ~$64/月"
      echo "  - Production EB 環境 (EC2 + ALB): ~$58/月"
      total_savings=$((total_savings + 122))
    fi
  done

  echo -e "  ${GREEN}總計: ~$$total_savings/月${NC}"
  echo ""
  echo "提示："
  echo "  - 請到 AWS Console 確認所有資源已刪除"
  echo "  - RDS 和 ElastiCache 約需 5-10 分鐘完全移除"
  echo "  - Security Groups 需要在關聯資源刪除後才能移除"
fi

echo ""
echo "結束時間: $(date)"
echo ""
