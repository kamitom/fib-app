#!/bin/bash
# 自動建立 IAM 使用者和 Access Key
set -e

USER_NAME="fib-app-deployer"

echo "================================================"
echo "建立 IAM 使用者：$USER_NAME"
echo "================================================"
echo ""

# 檢查使用者是否已存在
if aws iam get-user --user-name $USER_NAME 2>/dev/null; then
  echo "⚠️  使用者 $USER_NAME 已存在"
  read -p "是否要建立新的 Access Key? (y/n): " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 0
  fi
else
  echo "✓ 建立使用者..."
  aws iam create-user --user-name $USER_NAME
  echo ""

  echo "✓ 附加權限..."
  # 使用 AdministratorAccess（學習階段）
  # 包含所有 AWS 服務的完整權限
  if aws iam attach-user-policy \
    --user-name $USER_NAME \
    --policy-arn arn:aws:iam::aws:policy/AdministratorAccess 2>/dev/null; then
    echo "  ✓ AdministratorAccess 附加成功"
  else
    echo "  ⚠️  權限附加失敗，請手動檢查"
  fi
  echo ""
fi

echo "✓ 建立 Access Key..."
OUTPUT=$(aws iam create-access-key --user-name $USER_NAME)

ACCESS_KEY_ID=$(echo $OUTPUT | jq -r '.AccessKey.AccessKeyId')
SECRET_ACCESS_KEY=$(echo $OUTPUT | jq -r '.AccessKey.SecretAccessKey')

echo ""
echo "================================================"
echo "✅ IAM 使用者建立完成！"
echo "================================================"
echo ""
echo "Access Key ID: $ACCESS_KEY_ID"
echo "Secret Access Key: $SECRET_ACCESS_KEY"
echo ""
echo "⚠️  請立即儲存這些資訊！Secret Access Key 只會顯示一次"
echo ""

# 自動設定 AWS profile
read -p "是否要自動設定 AWS profile 'fib-deployer'? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  aws configure set aws_access_key_id $ACCESS_KEY_ID --profile fib-deployer
  aws configure set aws_secret_access_key $SECRET_ACCESS_KEY --profile fib-deployer
  aws configure set region ap-northeast-1 --profile fib-deployer
  aws configure set output json --profile fib-deployer

  echo ""
  echo "✓ Profile 'fib-deployer' 設定完成"
  echo ""
  echo "測試連線："
  aws sts get-caller-identity --profile fib-deployer
  echo ""
  echo "下一步執行："
  echo "  export AWS_PROFILE=fib-deployer"
  echo "  ./scripts/setup-aws-infrastructure.sh"
fi

echo ""
echo "GitHub Secrets 需要的資訊："
echo "  AWS_ACCESS_KEY_ID=$ACCESS_KEY_ID"
echo "  AWS_SECRET_ACCESS_KEY=$SECRET_ACCESS_KEY"
echo "  AWS_REGION=ap-northeast-1"
echo ""
