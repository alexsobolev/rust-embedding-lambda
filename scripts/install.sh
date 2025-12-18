#!/bin/bash
set -e

# Configuration
AWS_REGION=${AWS_REGION:-"eu-central-1"}
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REPO_NAME="embedding-lambda"
FUNCTION_NAME="embedding-lambda"
ROLE_NAME="embedding-lambda-role"
ECR_URI="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$REPO_NAME"

echo "--------------------------------------------------"
echo "🚀 Starting Embedding Lambda Setup from Scratch"
echo "Region: $AWS_REGION"
echo "Account: $AWS_ACCOUNT_ID"
# 0. Pre-flight Checks
echo "🔹 Step 0: Pre-flight Checks..."
if [ ! -f "model/model_quantized.onnx" ] || [ ! -f "model/tokenizer.json" ]; then
    echo "❌ Error: Model files not found in model/ directory."
    echo "Please download them from Hugging Face or ensure they are present."
    echo "Expected: model/model_quantized.onnx and model/tokenizer.json"
    exit 1
fi
echo "✅ Model files found."

# 1. IAM Role Setup
echo "🔹 Step 1: Setting up IAM Role..."
if ! aws iam get-role --role-name $ROLE_NAME > /dev/null 2>&1; then
    echo "Creating role $ROLE_NAME..."
    aws iam create-role --role-name $ROLE_NAME --assume-role-policy-document file://scripts/trust-policy.json
    echo "Waiting for role propagation..."
    sleep 10
else
    echo "Role $ROLE_NAME already exists."
fi

echo "Attaching execution policy..."
aws iam attach-role-policy \
  --role-name $ROLE_NAME \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

# 2. ECR Setup
echo "🔹 Step 2: Setting up ECR Repository..."
if ! aws ecr describe-repositories --repository-names $REPO_NAME --region $AWS_REGION > /dev/null 2>&1; then
    echo "Creating repository $REPO_NAME..."
    aws ecr create-repository --repository-name $REPO_NAME --region $AWS_REGION
else
    echo "Repository $REPO_NAME already exists."
fi

echo "Authenticating Docker with ECR..."
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# 3. Build and Push Image
echo "🔹 Step 3: Building and Pushing ARM64 Image..."
docker build --platform linux/arm64 -t $REPO_NAME .
docker tag $REPO_NAME:latest $ECR_URI:latest
docker push $ECR_URI:latest

# 4. Lambda Function Setup
echo "🔹 Step 4: Setting up Lambda Function..."
if ! aws lambda get-function --function-name $FUNCTION_NAME --region $AWS_REGION > /dev/null 2>&1; then
    echo "Creating function $FUNCTION_NAME..."
    aws lambda create-function \
      --function-name $FUNCTION_NAME \
      --package-type Image \
      --code ImageUri=$ECR_URI:latest \
      --role arn:aws:iam::$AWS_ACCOUNT_ID:role/$ROLE_NAME \
      --architectures arm64 \
      --memory-size 2048 \
      --timeout 120 \
      --region $AWS_REGION
    
    echo "Waiting for function to be active..."
    aws lambda wait function-active --function-name $FUNCTION_NAME --region $AWS_REGION
else
    echo "Function $FUNCTION_NAME already exists. Updating code..."
    aws lambda update-function-code \
      --function-name $FUNCTION_NAME \
      --image-uri $ECR_URI:latest \
      --region $AWS_REGION
    
    aws lambda wait function-updated --function-name $FUNCTION_NAME --region $AWS_REGION
fi

# 5. Function URL Configuration
echo "🔹 Step 5: Configuring Function URL..."
if ! aws lambda get-function-url-config --function-name $FUNCTION_NAME --region $AWS_REGION > /dev/null 2>&1; then
    echo "Creating Function URL with IAM Auth..."
    aws lambda create-function-url-config \
      --function-name $FUNCTION_NAME \
      --auth-type AWS_IAM \
      --invoke-mode BUFFERED \
      --region $AWS_REGION
else
    echo "Function URL already configured."
fi

echo "Updating Function URL Permissions..."
aws lambda add-permission \
  --function-name $FUNCTION_NAME \
  --statement-id AllowFunctionURLInvoke \
  --action lambda:InvokeFunctionUrl \
  --principal "*" \
  --function-url-auth-type AWS_IAM \
  --region $AWS_REGION > /dev/null 2>&1 || true

# 6. CloudWatch Logs Setup
echo "🔹 Step 6: Setting up CloudWatch Logs..."
if ! aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/$FUNCTION_NAME" --region $AWS_REGION | grep -q "/aws/lambda/$FUNCTION_NAME"; then
    echo "Creating log group..."
    aws logs create-log-group --log-group-name "/aws/lambda/$FUNCTION_NAME" --region $AWS_REGION || true
fi
echo "Setting log retention to 14 days..."
aws logs put-retention-policy --log-group-name "/aws/lambda/$FUNCTION_NAME" --retention-in-days 14 --region $AWS_REGION

# 7. Final Summary
URL=$(aws lambda get-function-url-config --function-name $FUNCTION_NAME --region $AWS_REGION --query 'FunctionUrl' --output text)

echo "--------------------------------------------------"
echo "✅ Setup Complete!"
echo "Function Name: $FUNCTION_NAME"
echo "Function URL:  $URL"
echo "Auth Type:     AWS_IAM"
echo "Region:        $AWS_REGION"
echo "--------------------------------------------------"
echo "💡 To test your function, run:"
echo "./scripts/test_with_iam.sh '{\"text\": \"Hello world\", \"size\": 256}'"
echo "--------------------------------------------------"
