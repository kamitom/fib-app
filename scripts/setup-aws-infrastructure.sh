#!/bin/bash
# AWS Infrastructure Setup Script for Fib-App
# Region: ap-northeast-1 (Tokyo)
#
# Prerequisites:
# - AWS CLI configured with appropriate credentials
# - Permissions: RDS, ElastiCache, ECR, Elastic Beanstalk, IAM, S3

set -e

# Disable AWS CLI pager to prevent interactive prompts
export AWS_PAGER=""

# Configuration
AWS_REGION="ap-northeast-1"
PROJECT_NAME="fib-app"


# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
  echo -e "${BLUE}================================================${NC}"
  echo -e "${BLUE}$1${NC}"
  echo -e "${BLUE}================================================${NC}"
}

print_success() {
  echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
  echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
  echo -e "${RED}✗ $1${NC}"
}

# Prompt for environment
echo ""
print_header "Fib-App AWS Infrastructure Setup"
echo ""
echo "請選擇要設置的環境："
echo "  1) Staging"
echo "  2) Production"
echo ""
read -p "選擇 (1 或 2): " env_choice

case $env_choice in
  1)
    ENVIRONMENT="staging"
    DB_INSTANCE_CLASS="db.t3.micro"
    CACHE_NODE_TYPE="cache.t3.micro"
    MULTI_AZ="false"
    BACKUP_RETENTION=7
    ;;
  2)
    ENVIRONMENT="production"
    DB_INSTANCE_CLASS="db.t3.small"
    CACHE_NODE_TYPE="cache.t3.small"
    MULTI_AZ="true"
    BACKUP_RETENTION=14
    ;;
  *)
    print_error "無效選擇"
    exit 1
    ;;
esac

# Database credentials
print_header "Step 1: 資料庫配置"
echo ""
read -p "PostgreSQL 主使用者名稱 [fib_${ENVIRONMENT}]: " DB_USERNAME
DB_USERNAME=${DB_USERNAME:-fib_${ENVIRONMENT}}

read -sp "PostgreSQL 主密碼（至少 8 字元）: " DB_PASSWORD
echo ""

if [ ${#DB_PASSWORD} -lt 8 ]; then
  print_error "密碼長度必須至少 8 字元"
  exit 1
fi

DB_NAME="fib_${ENVIRONMENT}"
RDS_INSTANCE_ID="${PROJECT_NAME}-${ENVIRONMENT}-db"
REDIS_CLUSTER_ID="${PROJECT_NAME}-${ENVIRONMENT}-redis"

print_success "配置完成"
echo ""

# Get AWS Account ID
print_header "Step 2: 驗證 AWS 帳戶"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
print_success "AWS Account ID: $AWS_ACCOUNT_ID"
print_success "AWS Region: $AWS_REGION"
echo ""

# Create VPC and Security Groups (simplified - using default VPC)
print_header "Step 3: 設置網路安全群組"
DEFAULT_VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=isDefault,Values=true" \
  --query 'Vpcs[0].VpcId' \
  --output text \
  --region $AWS_REGION)

print_success "使用 Default VPC: $DEFAULT_VPC_ID"

# Create security group for RDS
RDS_SG_NAME="${PROJECT_NAME}-${ENVIRONMENT}-rds-sg"
RDS_SG_ID=$(aws ec2 create-security-group \
  --group-name $RDS_SG_NAME \
  --description "Security group for RDS PostgreSQL (${ENVIRONMENT})" \
  --vpc-id $DEFAULT_VPC_ID \
  --region $AWS_REGION \
  --query 'GroupId' \
  --output text 2>/dev/null || \
  aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=$RDS_SG_NAME" \
    --query 'SecurityGroups[0].GroupId' \
    --output text \
    --region $AWS_REGION)

print_success "RDS Security Group: $RDS_SG_ID"

# Create security group for ElastiCache
REDIS_SG_NAME="${PROJECT_NAME}-${ENVIRONMENT}-redis-sg"
REDIS_SG_ID=$(aws ec2 create-security-group \
  --group-name $REDIS_SG_NAME \
  --description "Security group for Redis (${ENVIRONMENT})" \
  --vpc-id $DEFAULT_VPC_ID \
  --region $AWS_REGION \
  --query 'GroupId' \
  --output text 2>/dev/null || \
  aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=$REDIS_SG_NAME" \
    --query 'SecurityGroups[0].GroupId' \
    --output text \
    --region $AWS_REGION)

print_success "Redis Security Group: $REDIS_SG_ID"

# Create security group for Elastic Beanstalk
EB_SG_NAME="${PROJECT_NAME}-${ENVIRONMENT}-eb-sg"
EB_SG_ID=$(aws ec2 create-security-group \
  --group-name $EB_SG_NAME \
  --description "Security group for Elastic Beanstalk (${ENVIRONMENT})" \
  --vpc-id $DEFAULT_VPC_ID \
  --region $AWS_REGION \
  --query 'GroupId' \
  --output text 2>/dev/null || \
  aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=$EB_SG_NAME" \
    --query 'SecurityGroups[0].GroupId' \
    --output text \
    --region $AWS_REGION)

print_success "Elastic Beanstalk Security Group: $EB_SG_ID"

# Configure security group rules
aws ec2 authorize-security-group-ingress \
  --group-id $RDS_SG_ID \
  --protocol tcp \
  --port 5432 \
  --source-group $EB_SG_ID \
  --region $AWS_REGION 2>/dev/null || true

aws ec2 authorize-security-group-ingress \
  --group-id $REDIS_SG_ID \
  --protocol tcp \
  --port 6379 \
  --source-group $EB_SG_ID \
  --region $AWS_REGION 2>/dev/null || true

print_success "安全群組規則配置完成"
echo ""

# Create RDS PostgreSQL
print_header "Step 4: 建立 RDS PostgreSQL 資料庫"
echo "這可能需要 10-15 分鐘..."
echo ""

aws rds create-db-instance \
  --db-instance-identifier $RDS_INSTANCE_ID \
  --db-instance-class $DB_INSTANCE_CLASS \
  --engine postgres \
  --engine-version 17.2 \
  --master-username $DB_USERNAME \
  --master-user-password $DB_PASSWORD \
  --allocated-storage 20 \
  --storage-type gp3 \
  --vpc-security-group-ids $RDS_SG_ID \
  --db-name $DB_NAME \
  --backup-retention-period $BACKUP_RETENTION \
  --multi-az \
  --no-publicly-accessible \
  --region $AWS_REGION \
  --tags Key=Environment,Value=$ENVIRONMENT Key=Project,Value=$PROJECT_NAME \
  2>/dev/null || print_warning "RDS instance may already exist"

print_success "RDS 建立指令已發送"
echo ""

# Create ElastiCache Redis
print_header "Step 5: 建立 ElastiCache Redis 叢集"
echo "這可能需要 5-10 分鐘..."
echo ""

aws elasticache create-cache-cluster \
  --cache-cluster-id $REDIS_CLUSTER_ID \
  --cache-node-type $CACHE_NODE_TYPE \
  --engine redis \
  --engine-version 7.1 \
  --num-cache-nodes 1 \
  --security-group-ids $REDIS_SG_ID \
  --region $AWS_REGION \
  --tags Key=Environment,Value=$ENVIRONMENT Key=Project,Value=$PROJECT_NAME \
  2>/dev/null || print_warning "Redis cluster may already exist"

print_success "Redis 建立指令已發送"
echo ""

# Create ECR Repositories
print_header "Step 6: 建立 ECR Repositories"

for repo in fib-fe fib-be fib-worker fib-nginx; do
  aws ecr create-repository \
    --repository-name $repo \
    --region $AWS_REGION \
    --tags Key=Environment,Value=$ENVIRONMENT Key=Project,Value=$PROJECT_NAME \
    2>/dev/null && print_success "Created ECR repository: $repo" || print_warning "Repository $repo may already exist"
done

echo ""

# Create S3 bucket for Elastic Beanstalk
print_header "Step 7: 建立 S3 Bucket"
S3_BUCKET="elasticbeanstalk-${AWS_REGION}-${AWS_ACCOUNT_ID}"

aws s3 mb s3://$S3_BUCKET --region $AWS_REGION 2>/dev/null && \
  print_success "Created S3 bucket: $S3_BUCKET" || \
  print_warning "S3 bucket may already exist"

echo ""

# Create IAM Instance Profile for Elastic Beanstalk
print_header "Step 8: 建立 IAM Instance Profile"

# Check if instance profile exists
INSTANCE_PROFILE_EXISTS=$(aws iam get-instance-profile \
  --instance-profile-name aws-elasticbeanstalk-ec2-role \
  --query 'InstanceProfile.InstanceProfileName' \
  --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$INSTANCE_PROFILE_EXISTS" = "NOT_FOUND" ]; then
  print_warning "IAM Instance Profile 不存在，正在建立..."

  # Create IAM role
  cat > /tmp/eb-ec2-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

  aws iam create-role \
    --role-name aws-elasticbeanstalk-ec2-role \
    --assume-role-policy-document file:///tmp/eb-ec2-trust-policy.json \
    2>/dev/null || true

  # Attach managed policies
  aws iam attach-role-policy \
    --role-name aws-elasticbeanstalk-ec2-role \
    --policy-arn arn:aws:iam::aws:policy/AWSElasticBeanstalkWebTier \
    2>/dev/null || true

  aws iam attach-role-policy \
    --role-name aws-elasticbeanstalk-ec2-role \
    --policy-arn arn:aws:iam::aws:policy/AWSElasticBeanstalkMulticontainerDocker \
    2>/dev/null || true

  aws iam attach-role-policy \
    --role-name aws-elasticbeanstalk-ec2-role \
    --policy-arn arn:aws:iam::aws:policy/AWSElasticBeanstalkWorkerTier \
    2>/dev/null || true

  # Add ECR pull permissions for ECS platform
  cat > /tmp/ecr-pull-policy.json << 'EOF'
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
EOF

  aws iam put-role-policy \
    --role-name aws-elasticbeanstalk-ec2-role \
    --policy-name ECR-Pull-Policy \
    --policy-document file:///tmp/ecr-pull-policy.json \
    2>/dev/null || true

  rm /tmp/ecr-pull-policy.json

  # Create instance profile
  aws iam create-instance-profile \
    --instance-profile-name aws-elasticbeanstalk-ec2-role \
    2>/dev/null || true

  # Add role to instance profile
  aws iam add-role-to-instance-profile \
    --instance-profile-name aws-elasticbeanstalk-ec2-role \
    --role-name aws-elasticbeanstalk-ec2-role \
    2>/dev/null || true

  rm /tmp/eb-ec2-trust-policy.json

  print_success "IAM Instance Profile 已建立"

  # Wait a bit for IAM propagation
  echo "等待 IAM 權限傳播..."
  sleep 10
else
  print_success "IAM Instance Profile 已存在"
fi

echo ""

# Create Elastic Beanstalk Application
print_header "Step 9: 建立 Elastic Beanstalk Application"

aws elasticbeanstalk create-application \
  --application-name $PROJECT_NAME \
  --description "Fibonacci Multi-Container Application" \
  --region $AWS_REGION \
  2>/dev/null && print_success "Created EB application" || print_warning "EB application may already exist"

echo ""

# Wait for resources
print_header "Step 10: 等待資源建立完成"
echo ""
echo "正在等待 RDS 資料庫啟動..."

aws rds wait db-instance-available \
  --db-instance-identifier $RDS_INSTANCE_ID \
  --region $AWS_REGION

print_success "RDS 資料庫已就緒"

echo ""
echo "正在等待 Redis 叢集啟動..."

aws elasticache wait cache-cluster-available \
  --cache-cluster-id $REDIS_CLUSTER_ID \
  --region $AWS_REGION

print_success "Redis 叢集已就緒"
echo ""

# Get endpoints
print_header "Step 11: 建立 Elastic Beanstalk Environment"
echo "這可能需要 5-8 分鐘..."
echo ""

# Get available subnets
SUBNETS=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$DEFAULT_VPC_ID" "Name=map-public-ip-on-launch,Values=true" \
  --region $AWS_REGION \
  --query 'Subnets[].SubnetId' \
  --output text | tr '\t' ',')

print_success "使用 Public Subnets: $SUBNETS"

# Create EB environment
EB_ENV_NAME="${PROJECT_NAME}-${ENVIRONMENT}"

# Check if environment already exists
EXISTING_ENV=$(aws elasticbeanstalk describe-environments \
  --application-name $PROJECT_NAME \
  --environment-names $EB_ENV_NAME \
  --region $AWS_REGION \
  --query 'Environments[?Status!=`Terminated`].EnvironmentName' \
  --output text 2>/dev/null)

if [ -n "$EXISTING_ENV" ]; then
  print_warning "EB Environment '$EB_ENV_NAME' already exists, skipping creation"
else
  # Create environment (using ECS platform for multi-container support)
  # Use JSON format for option-settings to avoid parameter parsing issues

  cat > /tmp/eb-options-${ENVIRONMENT}.json << EOF
[
  {
    "Namespace": "aws:autoscaling:launchconfiguration",
    "OptionName": "IamInstanceProfile",
    "Value": "aws-elasticbeanstalk-ec2-role"
  },
  {
    "Namespace": "aws:autoscaling:launchconfiguration",
    "OptionName": "InstanceType",
    "Value": "t3.small"
  },
  {
    "Namespace": "aws:autoscaling:launchconfiguration",
    "OptionName": "SecurityGroups",
    "Value": "$EB_SG_ID"
  },
  {
    "Namespace": "aws:autoscaling:asg",
    "OptionName": "MinSize",
    "Value": "1"
  },
  {
    "Namespace": "aws:autoscaling:asg",
    "OptionName": "MaxSize",
    "Value": "2"
  },
  {
    "Namespace": "aws:ec2:vpc",
    "OptionName": "VPCId",
    "Value": "$DEFAULT_VPC_ID"
  },
  {
    "Namespace": "aws:ec2:vpc",
    "OptionName": "Subnets",
    "Value": "$SUBNETS"
  },
  {
    "Namespace": "aws:ec2:vpc",
    "OptionName": "ELBSubnets",
    "Value": "$SUBNETS"
  },
  {
    "Namespace": "aws:elasticbeanstalk:environment",
    "OptionName": "EnvironmentType",
    "Value": "LoadBalanced"
  },
  {
    "Namespace": "aws:elasticbeanstalk:environment",
    "OptionName": "LoadBalancerType",
    "Value": "application"
  },
  {
    "Namespace": "aws:elbv2:loadbalancer",
    "OptionName": "SecurityGroups",
    "Value": "$EB_SG_ID"
  },
  {
    "Namespace": "aws:elasticbeanstalk:healthreporting:system",
    "OptionName": "SystemType",
    "Value": "enhanced"
  }
]
EOF

  aws elasticbeanstalk create-environment \
    --application-name $PROJECT_NAME \
    --environment-name $EB_ENV_NAME \
    --solution-stack-name "64bit Amazon Linux 2023 v4.3.1 running ECS" \
    --tier Name=WebServer,Type=Standard \
    --option-settings file:///tmp/eb-options-${ENVIRONMENT}.json \
    --region $AWS_REGION \
    --tags Key=Environment,Value=$ENVIRONMENT Key=Project,Value=$PROJECT_NAME

  rm /tmp/eb-options-${ENVIRONMENT}.json

  print_success "EB Environment 建立指令已發送"

  echo ""
  echo "等待 EB Environment 就緒..."

  aws elasticbeanstalk wait environment-updated \
    --application-name $PROJECT_NAME \
    --environment-names $EB_ENV_NAME \
    --region $AWS_REGION

  print_success "EB Environment 已就緒"

  # Fix S3 bucket ACL settings for EB deployments
  echo ""
  echo "修復 S3 Bucket ACL 設定..."
  S3_BUCKET="elasticbeanstalk-${REGION}-${ACCOUNT_ID}"

  aws s3api put-bucket-ownership-controls \
    --bucket $S3_BUCKET \
    --region $REGION \
    --ownership-controls 'Rules=[{ObjectOwnership=ObjectWriter}]' 2>/dev/null || true

  print_success "S3 Bucket ACL 設定已更新"
fi

echo ""

# Get endpoints
print_header "Step 12: 取得資源端點"

RDS_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier $RDS_INSTANCE_ID \
  --region $AWS_REGION \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

REDIS_ENDPOINT=$(aws elasticache describe-cache-clusters \
  --cache-cluster-id $REDIS_CLUSTER_ID \
  --region $AWS_REGION \
  --show-cache-node-info \
  --query 'CacheClusters[0].CacheNodes[0].Endpoint.Address' \
  --output text)

EB_URL=$(aws elasticbeanstalk describe-environments \
  --application-name $PROJECT_NAME \
  --environment-names $EB_ENV_NAME \
  --region $AWS_REGION \
  --query 'Environments[0].CNAME' \
  --output text)

ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

print_success "RDS Endpoint: $RDS_ENDPOINT"
print_success "Redis Endpoint: $REDIS_ENDPOINT"
print_success "ECR Registry: $ECR_REGISTRY"
print_success "EB Environment URL: http://$EB_URL"
echo ""

# Output summary
print_header "✅ Infrastructure Setup Complete!"
echo ""
echo "請將以下資訊加入 GitHub Secrets:"
echo ""
echo "AWS_ACCESS_KEY_ID=<your-iam-access-key>"
echo "AWS_SECRET_ACCESS_KEY=<your-iam-secret-key>"
echo "AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID"
echo "AWS_REGION=$AWS_REGION"
echo "ECR_REGISTRY=$ECR_REGISTRY"
echo ""
if [ "$ENVIRONMENT" = "staging" ]; then
  echo "STAGING_RDS_ENDPOINT=$RDS_ENDPOINT"
  echo "STAGING_REDIS_ENDPOINT=$REDIS_ENDPOINT"
  echo "STAGING_DB_PASSWORD=$DB_PASSWORD"
else
  echo "PRODUCTION_RDS_ENDPOINT=$RDS_ENDPOINT"
  echo "PRODUCTION_REDIS_ENDPOINT=$REDIS_ENDPOINT"
  echo "PRODUCTION_DB_PASSWORD=$DB_PASSWORD"
fi
echo ""
echo "=========================================="
echo "測試 Environment（當前為 sample application）："
echo "  curl http://$EB_URL"
echo ""
echo "下一步："
echo "1. 設定 GitHub Secrets（如上）"
echo "2. 推送至 develop (staging) 或 main (production) 分支觸發 CD 部署"
echo "3. GitHub Actions 會自動 build、push ECR、部署到 EB Environment"
echo ""
echo "部署完成後測試："
echo "  curl http://$EB_URL/api/health"
echo ""
echo "=========================================="
echo ""
print_success "完成！所有基礎設施和 EB Environment 已就緒！"
echo ""
echo "結束時間: $(date)"
