#!/bin/bash
set -e

AWS_REGION=eu-central-1
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REPO_NAME=embedding-lambda
FUNCTION_NAME=embedding-lambda
ECR_URI="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$REPO_NAME"

echo "Logging in to ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

echo "Building Docker image..."
# Use --provenance=false to avoid issues with multi-platform builds in some setups
docker build --platform linux/arm64 -t $REPO_NAME .

echo "Tagging image..."
docker tag $REPO_NAME:latest $ECR_URI:latest

echo "Pushing to ECR..."
docker push $ECR_URI:latest

echo "Updating Lambda function configuration..."
aws lambda update-function-configuration \
  --function-name $FUNCTION_NAME \
  --memory-size 2048 \
  --region $AWS_REGION

echo "Updating Lambda function code..."
aws lambda update-function-code \
  --function-name $FUNCTION_NAME \
  --image-uri $ECR_URI:latest \
  --region $AWS_REGION

echo "Deployment complete!"
