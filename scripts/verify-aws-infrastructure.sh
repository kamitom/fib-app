#!/bin/bash
# Verify AWS Infrastructure Script
# 用途：驗證所有資源是否成功建立且狀態正常

set -e

# Disable pager
export AWS_PAGER=""

REGION="ap-northeast-1"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}AWS Infrastructure Verification${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""

# Prompt for environment
echo "請選擇要驗證的環境："
echo "  1) Staging"
echo "  2) Production"
echo ""
read -p "選擇 (1 或 2): " env_choice

case $env_choice in
  1)
    ENVIRONMENT="staging"
    ;;
  2)
    ENVIRONMENT="production"
    ;;
  *)
    echo -e "${RED}✗ 無效選擇${NC}"
    exit 1
    ;;
esac

echo ""
echo -e "${BLUE}驗證 ${ENVIRONMENT} 環境資源...${NC}"
echo ""

# Resource identifiers
RDS_ID="fib-app-${ENVIRONMENT}-db"
REDIS_ID="fib-app-${ENVIRONMENT}-redis"
EB_APP="fib-app"
EB_ENV="fib-app-${ENVIRONMENT}"

SUCCESS_COUNT=0
FAIL_COUNT=0
TOTAL_CHECKS=10

# Helper functions
check_success() {
  echo -e "${GREEN}✓ $1${NC}"
  ((SUCCESS_COUNT++))
}

check_fail() {
  echo -e "${RED}✗ $1${NC}"
  ((FAIL_COUNT++))
}

check_warning() {
  echo -e "${YELLOW}⚠ $1${NC}"
}

# 1. Check RDS
echo -e "${BLUE}[1/10] 檢查 RDS PostgreSQL...${NC}"
RDS_STATUS=$(aws rds describe-db-instances \
  --db-instance-identifier $RDS_ID \
  --region $REGION \
  --query 'DBInstances[0].DBInstanceStatus' \
  --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$RDS_STATUS" = "available" ]; then
  RDS_ENDPOINT=$(aws rds describe-db-instances \
    --db-instance-identifier $RDS_ID \
    --region $REGION \
    --query 'DBInstances[0].Endpoint.Address' \
    --output text)
  check_success "RDS 狀態: available"
  echo "   Endpoint: $RDS_ENDPOINT"
elif [ "$RDS_STATUS" = "NOT_FOUND" ]; then
  check_fail "RDS 不存在"
else
  check_warning "RDS 狀態: $RDS_STATUS (可能仍在建立中)"
fi
echo ""

# 2. Check ElastiCache Redis
echo -e "${BLUE}[2/10] 檢查 ElastiCache Redis...${NC}"
REDIS_STATUS=$(aws elasticache describe-cache-clusters \
  --cache-cluster-id $REDIS_ID \
  --region $REGION \
  --query 'CacheClusters[0].CacheClusterStatus' \
  --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$REDIS_STATUS" = "available" ]; then
  REDIS_ENDPOINT=$(aws elasticache describe-cache-clusters \
    --cache-cluster-id $REDIS_ID \
    --region $REGION \
    --show-cache-node-info \
    --query 'CacheClusters[0].CacheNodes[0].Endpoint.Address' \
    --output text)
  check_success "Redis 狀態: available"
  echo "   Endpoint: $REDIS_ENDPOINT"
elif [ "$REDIS_STATUS" = "NOT_FOUND" ]; then
  check_fail "Redis 不存在"
else
  check_warning "Redis 狀態: $REDIS_STATUS (可能仍在建立中)"
fi
echo ""

# 3. Check ECR Repositories
echo -e "${BLUE}[3/10] 檢查 ECR Repositories...${NC}"
EXPECTED_REPOS=("fib-fe" "fib-be" "fib-worker" "fib-nginx")
ECR_MISSING=0

for repo in "${EXPECTED_REPOS[@]}"; do
  REPO_EXISTS=$(aws ecr describe-repositories \
    --repository-names $repo \
    --region $REGION \
    --query 'repositories[0].repositoryName' \
    --output text 2>/dev/null || echo "NOT_FOUND")

  if [ "$REPO_EXISTS" = "$repo" ]; then
    echo -e "   ${GREEN}✓${NC} $repo"
  else
    echo -e "   ${RED}✗${NC} $repo (不存在)"
    ((ECR_MISSING++))
  fi
done

if [ $ECR_MISSING -eq 0 ]; then
  check_success "所有 ECR repositories 存在"
else
  check_fail "$ECR_MISSING 個 ECR repositories 缺失"
fi
echo ""

# 4. Check S3 Bucket
echo -e "${BLUE}[4/10] 檢查 S3 Bucket...${NC}"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
S3_BUCKET="elasticbeanstalk-${REGION}-${AWS_ACCOUNT_ID}"

S3_EXISTS=$(aws s3 ls s3://$S3_BUCKET 2>/dev/null && echo "EXISTS" || echo "NOT_FOUND")

if [ "$S3_EXISTS" = "EXISTS" ]; then
  check_success "S3 Bucket 存在: $S3_BUCKET"
else
  check_fail "S3 Bucket 不存在"
fi
echo ""

# 5. Check Elastic Beanstalk Application
echo -e "${BLUE}[5/10] 檢查 EB Application...${NC}"
EB_APP_EXISTS=$(aws elasticbeanstalk describe-applications \
  --application-names $EB_APP \
  --region $REGION \
  --query 'Applications[0].ApplicationName' \
  --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$EB_APP_EXISTS" = "$EB_APP" ]; then
  check_success "EB Application 存在"
else
  check_fail "EB Application 不存在"
fi
echo ""

# 6. Check Elastic Beanstalk Environment
echo -e "${BLUE}[6/10] 檢查 EB Environment...${NC}"
EB_ENV_STATUS=$(aws elasticbeanstalk describe-environments \
  --application-name $EB_APP \
  --environment-names $EB_ENV \
  --region $REGION \
  --query 'Environments[0].Status' \
  --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$EB_ENV_STATUS" = "Ready" ]; then
  EB_HEALTH=$(aws elasticbeanstalk describe-environments \
    --application-name $EB_APP \
    --environment-names $EB_ENV \
    --region $REGION \
    --query 'Environments[0].Health' \
    --output text)

  EB_URL=$(aws elasticbeanstalk describe-environments \
    --application-name $EB_APP \
    --environment-names $EB_ENV \
    --region $REGION \
    --query 'Environments[0].CNAME' \
    --output text)

  check_success "EB Environment 狀態: Ready"
  echo "   Health: $EB_HEALTH"
  echo "   URL: http://$EB_URL"
elif [ "$EB_ENV_STATUS" = "NOT_FOUND" ]; then
  check_fail "EB Environment 不存在"
else
  check_warning "EB Environment 狀態: $EB_ENV_STATUS (可能仍在建立中)"
fi
echo ""

# 7. Check Security Groups
echo -e "${BLUE}[7/10] 檢查 Security Groups...${NC}"
SG_NAMES=("fib-app-${ENVIRONMENT}-rds-sg" "fib-app-${ENVIRONMENT}-redis-sg" "fib-app-${ENVIRONMENT}-eb-sg")
SG_MISSING=0

for sg_name in "${SG_NAMES[@]}"; do
  SG_EXISTS=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=$sg_name" \
    --region $REGION \
    --query 'SecurityGroups[0].GroupId' \
    --output text 2>/dev/null || echo "NOT_FOUND")

  if [ "$SG_EXISTS" != "NOT_FOUND" ] && [ "$SG_EXISTS" != "None" ]; then
    echo -e "   ${GREEN}✓${NC} $sg_name ($SG_EXISTS)"
  else
    echo -e "   ${RED}✗${NC} $sg_name (不存在)"
    ((SG_MISSING++))
  fi
done

if [ $SG_MISSING -eq 0 ]; then
  check_success "所有 Security Groups 存在"
else
  check_fail "$SG_MISSING 個 Security Groups 缺失"
fi
echo ""

# 8. Check RDS Connectivity (via Security Group)
echo -e "${BLUE}[8/10] 檢查 RDS Security Group 規則...${NC}"
RDS_SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=fib-app-${ENVIRONMENT}-rds-sg" \
  --region $REGION \
  --query 'SecurityGroups[0].GroupId' \
  --output text 2>/dev/null)

if [ "$RDS_SG_ID" != "None" ] && [ -n "$RDS_SG_ID" ]; then
  INGRESS_RULES=$(aws ec2 describe-security-group-rules \
    --filters "Name=group-id,Values=$RDS_SG_ID" "Name=is-egress,Values=false" \
    --region $REGION \
    --query 'SecurityGroupRules[?FromPort==`5432`]' \
    --output text 2>/dev/null)

  if [ -n "$INGRESS_RULES" ]; then
    check_success "RDS 允許從 EB 訪問 (port 5432)"
  else
    check_fail "RDS 缺少 ingress 規則"
  fi
else
  check_fail "無法檢查 RDS Security Group"
fi
echo ""

# 9. Check Redis Connectivity (via Security Group)
echo -e "${BLUE}[9/10] 檢查 Redis Security Group 規則...${NC}"
REDIS_SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=fib-app-${ENVIRONMENT}-redis-sg" \
  --region $REGION \
  --query 'SecurityGroups[0].GroupId' \
  --output text 2>/dev/null)

if [ "$REDIS_SG_ID" != "None" ] && [ -n "$REDIS_SG_ID" ]; then
  INGRESS_RULES=$(aws ec2 describe-security-group-rules \
    --filters "Name=group-id,Values=$REDIS_SG_ID" "Name=is-egress,Values=false" \
    --region $REGION \
    --query 'SecurityGroupRules[?FromPort==`6379`]' \
    --output text 2>/dev/null)

  if [ -n "$INGRESS_RULES" ]; then
    check_success "Redis 允許從 EB 訪問 (port 6379)"
  else
    check_fail "Redis 缺少 ingress 規則"
  fi
else
  check_fail "無法檢查 Redis Security Group"
fi
echo ""

# 10. Summary
echo -e "${BLUE}[10/10] 生成摘要...${NC}"
echo ""
echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}驗證摘要${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""
echo -e "環境: ${YELLOW}${ENVIRONMENT}${NC}"
echo -e "成功: ${GREEN}${SUCCESS_COUNT}/${TOTAL_CHECKS}${NC}"
echo -e "失敗: ${RED}${FAIL_COUNT}/${TOTAL_CHECKS}${NC}"
echo ""

if [ $FAIL_COUNT -eq 0 ] && [ $SUCCESS_COUNT -eq $TOTAL_CHECKS ]; then
  echo -e "${GREEN}✓ 所有資源驗證成功！${NC}"
  echo ""
  echo "下一步："
  echo "1. 設定 GitHub Secrets"
  echo "2. 建立 develop 分支 (staging) 或推送至 main (production)"
  echo "3. 觸發 GitHub Actions CD 部署"
  exit 0
elif [ $FAIL_COUNT -gt 0 ]; then
  echo -e "${RED}✗ 有 $FAIL_COUNT 個資源驗證失敗${NC}"
  echo ""
  echo "建議："
  echo "1. 檢查腳本執行日誌"
  echo "2. 前往 AWS Console 手動確認"
  echo "3. 可能需要重新執行 setup 腳本"
  exit 1
else
  echo -e "${YELLOW}⚠ 部分資源可能仍在建立中${NC}"
  echo ""
  echo "建議："
  echo "1. 等待 5-10 分鐘後重新驗證"
  echo "2. 檢查 AWS Console 確認資源狀態"
  exit 2
fi
