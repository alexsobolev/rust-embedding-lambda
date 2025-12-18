AWS_REGION=eu-central-1
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REPO_NAME=embedding-lambda
FUNCTION_NAME=embedding-lambda

aws lambda create-function \
  --function-name $FUNCTION_NAME \
  --package-type Image \
  --code ImageUri=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$REPO_NAME:latest \
  --role arn:aws:iam::$AWS_ACCOUNT_ID:role/embedding-lambda-role \
  --architectures arm64 \
  --memory-size 2048 \
  --timeout 120 \
  --region $AWS_REGION
