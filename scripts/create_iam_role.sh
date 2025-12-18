# Check if role exists
if ! aws iam get-role --role-name embedding-lambda-role > /dev/null 2>&1; then
  # Create the role
  aws iam create-role \
    --role-name embedding-lambda-role \
    --assume-role-policy-document file://scripts/trust-policy.json
else
  echo "Role embedding-lambda-role already exists. Skipping creation."
fi

# Attach basic execution policy for CloudWatch logs
aws iam attach-role-policy \
  --role-name embedding-lambda-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
