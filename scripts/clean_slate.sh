#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

AWS_REGION=eu-central-1
FUNCTION_NAME=embedding-lambda
ROLE_NAME=embedding-lambda-role
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "Deleting resources..."
aws lambda delete-function-url-config --function-name $FUNCTION_NAME --region $AWS_REGION || true
aws lambda delete-function --function-name $FUNCTION_NAME --region $AWS_REGION || true
aws iam detach-role-policy --role-name $ROLE_NAME --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole || true
aws iam delete-role --role-name $ROLE_NAME || true

sleep 5

echo "Creating Role..."
"$SCRIPT_DIR/create_iam_role.sh"

sleep 15

echo "Creating Function (ARM64)..."
IMAGE_URI="$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$FUNCTION_NAME:latest"

aws lambda create-function \
  --function-name $FUNCTION_NAME \
  --package-type Image \
  --code ImageUri=$IMAGE_URI \
  --role arn:aws:iam::$ACCOUNT_ID:role/$ROLE_NAME \
  --architectures arm64 \
  --memory-size 2048 \
  --timeout 120 \
  --region $AWS_REGION

echo "Waiting for Active..."
aws lambda wait function-active --function-name $FUNCTION_NAME --region $AWS_REGION

echo "Creating URL..."
aws lambda create-function-url-config \
  --function-name $FUNCTION_NAME \
  --auth-type AWS_IAM \
  --invoke-mode BUFFERED \
  --region $AWS_REGION

echo "Testing..."
"$SCRIPT_DIR/test_with_iam.sh"
