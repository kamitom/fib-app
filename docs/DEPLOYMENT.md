# Deployment Guide

## Overview

This guide covers deploying the Fibonacci multi-container application to AWS Elastic Beanstalk.

## Prerequisites

Before deploying, ensure you have completed **Option B** (稳健 CD 準備):

✅ Health check endpoints ([fib-be/main.py:130](../fib-be/main.py#L130), [fib-worker/index.js:20](../fib-worker/index.js#L20))
✅ Integration tests ([tests/test_integration.py](../tests/test_integration.py))
✅ Database schema documentation ([DATABASE.md](./DATABASE.md))
✅ Environment configurations (`.env.staging.example`, `.env.production.example`)

## Deployment Strategy: AWS Elastic Beanstalk

### Why Elastic Beanstalk?

- **Native multi-container support** via `Dockerrun.aws.json`
- **Zero architecture changes** - uses existing docker-compose setup
- **Managed infrastructure** - auto-scaling, load balancing, health checks
- **RDS & ElastiCache integration** - managed PostgreSQL and Redis

### Architecture

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

## Infrastructure Setup

### 1. Create RDS PostgreSQL Instance

```bash
# AWS Console: RDS > Create Database
Engine: PostgreSQL 17
Template: Dev/Test (staging) or Production
Instance class: db.t3.micro (staging) or db.t3.small (production)
Storage: 20 GB SSD
Multi-AZ: No (staging) / Yes (production)
Database name: fib_staging / fib_production
Master username: fib_staging / fib_prod
Master password: <strong-password>

# Enable automatic backups
Backup retention: 7 days
```

**Get RDS Endpoint:**
```bash
aws rds describe-db-instances \
  --db-instance-identifier fib-staging \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text
```

### 2. Create ElastiCache Redis Cluster

```bash
# AWS Console: ElastiCache > Create Redis cluster
Engine: Redis 7.x
Node type: cache.t3.micro (staging) or cache.t3.small (production)
Number of replicas: 0 (staging) / 2 (production)
Multi-AZ: No (staging) / Yes (production)

# Enable automatic backups (production only)
Snapshot retention: 5 days
```

**Get Redis Endpoint:**
```bash
aws elasticache describe-cache-clusters \
  --cache-cluster-id fib-staging-redis \
  --show-cache-node-info \
  --query 'CacheClusters[0].CacheNodes[0].Endpoint.Address' \
  --output text
```

### 3. Create Elastic Container Registry (ECR)

```bash
# Create 4 ECR repositories
aws ecr create-repository --repository-name fib-fe
aws ecr create-repository --repository-name fib-be
aws ecr create-repository --repository-name fib-worker
aws ecr create-repository --repository-name fib-nginx

# Get login command
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-east-1.amazonaws.com
```

### 4. Configure GitHub Secrets

Add to repository Settings > Secrets and variables > Actions:

```
AWS_ACCESS_KEY_ID=<IAM_user_key>
AWS_SECRET_ACCESS_KEY=<IAM_user_secret>
AWS_REGION=us-east-1
ECR_REGISTRY=<account-id>.dkr.ecr.us-east-1.amazonaws.com

# Staging
STAGING_RDS_ENDPOINT=<rds-endpoint>
STAGING_REDIS_ENDPOINT=<redis-endpoint>
STAGING_DB_PASSWORD=<password>

# Production
PRODUCTION_RDS_ENDPOINT=<rds-endpoint>
PRODUCTION_REDIS_ENDPOINT=<redis-endpoint>
PRODUCTION_DB_PASSWORD=<password>
```

## Dockerrun.aws.json Configuration

Create `Dockerrun.aws.json` for Elastic Beanstalk multi-container deployment:

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

Create `.github/workflows/deploy-staging.yml`:

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
          # Generate Dockerrun.aws.json with image tags
          # Deploy to EB environment
          eb deploy fib-staging --staged
```

## Health Checks

Elastic Beanstalk health checks:

```
Target: HTTP:80/api/health
Healthy threshold: 2
Unhealthy threshold: 5
Timeout: 5 seconds
Interval: 30 seconds
```

Expected response:
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

## Monitoring

- **CloudWatch Logs**: Application logs from all containers
- **CloudWatch Metrics**: CPU, memory, request count, latency
- **X-Ray**: Distributed tracing (optional)
- **RDS Metrics**: Database connections, IOPS, storage
- **ElastiCache Metrics**: Cache hits, evictions, connections

## Rollback

```bash
# List deployments
eb appversion lifecycle -v

# Rollback to previous version
eb deploy fib-staging --version <version-label>
```

## Cost Estimation (Staging)

- **EC2 (t3.small)**: $15/month
- **RDS (db.t3.micro)**: $15/month
- **ElastiCache (cache.t3.micro)**: $12/month
- **ALB**: $20/month
- **Data transfer**: ~$5/month
- **Total**: ~$67/month

## Next Steps

1. ✅ Complete Option B preparations (this document assumes completion)
2. ⬜ Create Dockerrun.aws.json template
3. ⬜ Set up AWS infrastructure (RDS, ElastiCache, ECR)
4. ⬜ Configure GitHub Secrets
5. ⬜ Create deploy-staging.yml workflow
6. ⬜ Test deployment to staging
7. ⬜ Create deploy-production.yml workflow
8. ⬜ Set up monitoring and alerts
