#!/bin/bash
set -e

REGION="eu-central-1"
FUNCTION_NAME="embedding-lambda"

# Get Function URL
echo "Fetching Function URL..."
URL=$(aws lambda get-function-url-config --function-name $FUNCTION_NAME --region $REGION --output text --query FunctionUrl)
echo "Calling URL: $URL"

# Get Credentials
# formatting as env-no-export allows handy evaluation
eval $(aws configure export-credentials --format env-no-export)

if [ -z "$AWS_ACCESS_KEY_ID" ]; then
    echo "Error: Could not retrieve AWS credentials."
    exit 1
fi

# Build curl command
# --aws-sigv4 requires curl 7.75.0+
# Syntax: --aws-sigv4 "provider1[:provider2[:region[:service]]]"
# We need "aws:amz:region:lambda"

SIGV4_PARAM="aws:amz:$REGION:lambda"

# Default data if not provided
DATA=${1:-'{"text": "Bash", "size": 128}'}

if [ -n "$AWS_SESSION_TOKEN" ]; then
    curl --request POST \
        --url "$URL" \
        --header "Content-Type: application/json" \
        --header "X-Amz-Security-Token: $AWS_SESSION_TOKEN" \
        --aws-sigv4 "$SIGV4_PARAM" \
        --user "$AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY" \
        --data "$DATA"
else
    curl --request POST \
        --url "$URL" \
        --header "Content-Type: application/json" \
        --aws-sigv4 "$SIGV4_PARAM" \
        --user "$AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY" \
        --data "$DATA"
fi

echo "" # Newline after response
