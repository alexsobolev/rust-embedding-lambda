AWS_REGION=eu-central-1
FUNCTION_NAME=embedding-lambda

aws lambda create-function-url-config \
  --function-name $FUNCTION_NAME \
  --auth-type AWS_IAM \
  --invoke-mode BUFFERED \
  --region $AWS_REGION
