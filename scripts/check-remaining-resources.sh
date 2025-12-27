#!/bin/bash
# Quick check for remaining AWS resources
# Usage: ./check-remaining-resources.sh [staging|production]

set -e
export AWS_PAGER=""

REGION="ap-northeast-1"
ENVIRONMENT=${1:-staging}

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo "================================================"
echo "檢查 ${ENVIRONMENT} 環境殘留資源"
echo "================================================"
echo ""

FOUND_RESOURCES=0

# Check EB Environment
echo -n "EB Environment: "
EB_ENV=$(aws elasticbeanstalk describe-environments \
  --application-name fib-app \
  --environment-names fib-app-${ENVIRONMENT} \
  --region $REGION \
  --query 'Environments[?Status!=`Terminated`].EnvironmentName' \
  --output text 2>/dev/null)

if [ -z "$EB_ENV" ]; then
  echo -e "${GREEN}✓ 已清理${NC}"
else
  echo -e "${RED}✗ 仍存在: $EB_ENV${NC}"
  ((FOUND_RESOURCES++))
fi

# Check RDS
echo -n "RDS PostgreSQL: "
RDS_STATUS=$(aws rds describe-db-instances \
  --db-instance-identifier fib-app-${ENVIRONMENT}-db \
  --region $REGION \
  --query 'DBInstances[0].DBInstanceStatus' \
  --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$RDS_STATUS" = "NOT_FOUND" ]; then
  echo -e "${GREEN}✓ 已清理${NC}"
else
  echo -e "${RED}✗ 狀態: $RDS_STATUS${NC}"
  ((FOUND_RESOURCES++))
fi

# Check Redis
echo -n "ElastiCache Redis: "
REDIS_STATUS=$(aws elasticache describe-cache-clusters \
  --cache-cluster-id fib-app-${ENVIRONMENT}-redis \
  --region $REGION \
  --query 'CacheClusters[0].CacheClusterStatus' \
  --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$REDIS_STATUS" = "NOT_FOUND" ]; then
  echo -e "${GREEN}✓ 已清理${NC}"
else
  echo -e "${RED}✗ 狀態: $REDIS_STATUS${NC}"
  ((FOUND_RESOURCES++))
fi

# Check Security Groups
echo -n "Security Groups: "
SG_COUNT=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=fib-app-${ENVIRONMENT}-*" \
  --region $REGION \
  --query 'length(SecurityGroups)' \
  --output text 2>/dev/null)

if [ "$SG_COUNT" = "0" ]; then
  echo -e "${GREEN}✓ 已清理${NC}"
else
  echo -e "${YELLOW}⚠ 仍有 $SG_COUNT 個 (可能需要等待 RDS/Redis 完全刪除)${NC}"
fi

# Check ECR (only if checking all resources)
if [ "$ENVIRONMENT" = "all" ] || [ "$2" = "--check-ecr" ]; then
  echo -n "ECR Repositories: "
  ECR_COUNT=$(aws ecr describe-repositories \
    --region $REGION \
    --query 'length(repositories[?contains(repositoryName, `fib`)])' \
    --output text 2>/dev/null || echo "0")

  if [ "$ECR_COUNT" = "0" ]; then
    echo -e "${GREEN}✓ 已清理${NC}"
  else
    echo -e "${RED}✗ 仍有 $ECR_COUNT 個${NC}"
    ((FOUND_RESOURCES++))
  fi
fi

# Check IAM Instance Profile
echo -n "IAM Instance Profile: "
IAM_EXISTS=$(aws iam get-instance-profile \
  --instance-profile-name aws-elasticbeanstalk-ec2-role \
  --query 'InstanceProfile.InstanceProfileName' \
  --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$IAM_EXISTS" = "NOT_FOUND" ]; then
  echo -e "${GREEN}✓ 已清理${NC}"
else
  echo -e "${YELLOW}⚠ 仍存在 (共用資源)${NC}"
fi

echo ""
echo "================================================"

if [ $FOUND_RESOURCES -eq 0 ]; then
  echo -e "${GREEN}✓ 所有主要資源已清理完成${NC}"
  echo ""
  echo "提示："
  echo "  - Security Groups 可能需要 5-10 分鐘後才能刪除"
  echo "  - 可前往 AWS Console 做最終確認"
  exit 0
else
  echo -e "${YELLOW}⚠ 發現 $FOUND_RESOURCES 個資源仍在刪除中${NC}"
  echo ""
  echo "建議："
  echo "  - 等待 5-10 分鐘後重新檢查"
  echo "  - 檢查 AWS Console 確認狀態"
  echo "  - 如持續存在，可能需要手動刪除"
  exit 1
fi
