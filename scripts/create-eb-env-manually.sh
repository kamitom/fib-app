#!/bin/bash
# Manual EB Environment creation script

set -e
export AWS_PAGER=""

aws elasticbeanstalk create-environment \
  --application-name fib-app \
  --environment-name fib-app-staging \
  --solution-stack-name "64bit Amazon Linux 2023 v4.3.1 running ECS" \
  --tier "Name=WebServer,Type=Standard" \
  --option-settings \
    "Namespace=aws:autoscaling:launchconfiguration,OptionName=IamInstanceProfile,Value=aws-elasticbeanstalk-ec2-role" \
    "Namespace=aws:autoscaling:launchconfiguration,OptionName=InstanceType,Value=t3.small" \
    "Namespace=aws:autoscaling:launchconfiguration,OptionName=SecurityGroups,Value=sg-045ebac1496574cff" \
    "Namespace=aws:autoscaling:asg,OptionName=MinSize,Value=1" \
    "Namespace=aws:autoscaling:asg,OptionName=MaxSize,Value=2" \
    "Namespace=aws:ec2:vpc,OptionName=VPCId,Value=vpc-0f0c66f5c29ab79d3" \
    "Namespace=aws:ec2:vpc,OptionName=Subnets,Value=subnet-06f4aaa023e066945,subnet-0c60d98748db17deb,subnet-0f2a111f9603650c4" \
    "Namespace=aws:ec2:vpc,OptionName=ELBSubnets,Value=subnet-06f4aaa023e066945,subnet-0c60d98748db17deb,subnet-0f2a111f9603650c4" \
    "Namespace=aws:elasticbeanstalk:environment,OptionName=EnvironmentType,Value=LoadBalanced" \
    "Namespace=aws:elasticbeanstalk:environment,OptionName=LoadBalancerType,Value=application" \
    "Namespace=aws:elbv2:loadbalancer,OptionName=SecurityGroups,Value=sg-045ebac1496574cff" \
    "Namespace=aws:elasticbeanstalk:healthreporting:system,OptionName=SystemType,Value=enhanced" \
    "Namespace=aws:elasticbeanstalk:managedactions,OptionName=ManagedActionsEnabled,Value=true" \
    "Namespace=aws:elasticbeanstalk:managedactions,OptionName=PreferredStartTime,Value=Sun:10:00" \
  --region ap-northeast-1 \
  --tags Key=Environment,Value=staging Key=Project,Value=fib-app

echo ""
echo "EB Environment creation started. Waiting..."
echo ""

aws elasticbeanstalk wait environment-updated \
  --application-name fib-app \
  --environment-names fib-app-staging \
  --region ap-northeast-1

echo ""
echo "✓ EB Environment is ready!"
