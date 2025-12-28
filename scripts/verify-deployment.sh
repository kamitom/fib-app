#!/bin/bash
# Verify staging deployment is successful

set -e

REGION="ap-northeast-1"
ENV_NAME="fib-app-staging"

echo "=========================================="
echo "驗證 Staging 部署狀態"
echo "=========================================="
echo ""

# 1. Check EB environment health
echo "1. 檢查 Elastic Beanstalk 環境健康..."
EB_HEALTH=$(aws elasticbeanstalk describe-environment-health \
  --environment-name $ENV_NAME \
  --region $REGION \
  --attribute-names HealthStatus \
  --query 'HealthStatus' \
  --output text)

echo "   環境健康狀態: $EB_HEALTH"

if [ "$EB_HEALTH" != "Ok" ]; then
  echo "   ⚠️  環境不健康，查看詳細原因..."
  aws elasticbeanstalk describe-environment-health \
    --environment-name $ENV_NAME \
    --region $REGION \
    --attribute-names All \
    --query 'Causes' \
    --output text
fi
echo ""

# 2. Check ECS task status
echo "2. 檢查 ECS Task 狀態..."
CLUSTER=$(aws elasticbeanstalk describe-environments \
  --environment-names $ENV_NAME \
  --region $REGION \
  --query 'Environments[0].CNAME' \
  --output text | cut -d. -f1)

TASK_ARN=$(aws ecs list-tasks \
  --cluster awseb-${ENV_NAME}-vpx3mum3mc \
  --region $REGION \
  --query 'taskArns[0]' \
  --output text 2>/dev/null || echo "")

if [ -n "$TASK_ARN" ] && [ "$TASK_ARN" != "None" ]; then
  echo "   Task ARN: $TASK_ARN"

  CONTAINERS=$(aws ecs describe-tasks \
    --cluster awseb-${ENV_NAME}-vpx3mum3mc \
    --tasks $TASK_ARN \
    --region $REGION \
    --query 'tasks[0].containers[*].[name,lastStatus]' \
    --output text)

  echo "   容器狀態:"
  echo "$CONTAINERS" | while read name status; do
    echo "     - $name: $status"
  done
else
  echo "   ⚠️  沒有運行中的 Task"
fi
echo ""

# 3. Test API endpoint
echo "3. 測試 API 端點..."
EB_URL=$(aws elasticbeanstalk describe-environments \
  --environment-names $ENV_NAME \
  --region $REGION \
  --query 'Environments[0].EndpointURL' \
  --output text)

echo "   環境 URL: http://$EB_URL"

echo "   測試 /api/health..."
HEALTH_RESPONSE=$(curl -s -w "\n%{http_code}" http://$EB_URL/api/health 2>/dev/null || echo "000")
HTTP_CODE=$(echo "$HEALTH_RESPONSE" | tail -1)
RESPONSE_BODY=$(echo "$HEALTH_RESPONSE" | head -n -1)

if [ "$HTTP_CODE" = "200" ]; then
  echo "   ✅ Health check 成功 (HTTP $HTTP_CODE)"
  echo "   回應: $RESPONSE_BODY"
else
  echo "   ❌ Health check 失敗 (HTTP $HTTP_CODE)"
  echo "   回應: $RESPONSE_BODY"
fi
echo ""

# 4. Check recent events
echo "4. 最近的 EB 事件（最新 5 條）..."
aws elasticbeanstalk describe-events \
  --environment-name $ENV_NAME \
  --region $REGION \
  --max-records 5 \
  --query 'Events[*].[EventDate,Severity,Message]' \
  --output text | while IFS=$'\t' read date severity message; do
    echo "   [$severity] $message"
  done
echo ""

# 5. Summary
echo "=========================================="
echo "驗證摘要"
echo "=========================================="

if [ "$EB_HEALTH" = "Ok" ] && [ "$HTTP_CODE" = "200" ]; then
  echo "✅ 部署成功！所有檢查通過"
  echo ""
  echo "可以訪問應用："
  echo "  - Frontend: http://$EB_URL"
  echo "  - API: http://$EB_URL/api/health"
  exit 0
else
  echo "❌ 部署有問題，需要進一步診斷"
  echo ""
  echo "建議檢查："
  echo "  1. 查看完整日誌: aws elasticbeanstalk request-environment-info ..."
  echo "  2. 檢查容器日誌"
  echo "  3. 驗證 GitHub Secrets 配置"
  exit 1
fi
