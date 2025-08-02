#!/bin/bash
set -e

echo "🔐 Step 1.5: Adding SQS Permissions for EventBridge Orchestrator"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Load configuration
if [ -f ".env" ]; then
    source .env
    echo -e "${GREEN}✅ Loaded configuration from .env${NC}"
    AWS_REGION=${AWS_REGION:-us-east-2}
    ENVIRONMENT=${ENVIRONMENT:-dev}
else
    echo -e "${YELLOW}⚠️  No .env file found. Using defaults...${NC}"
    AWS_REGION="us-east-2"
    ENVIRONMENT="dev"
fi

# Get current user
CURRENT_USER=${AWS_USER:-$(aws sts get-caller-identity --query 'Arn' --output text | cut -d'/' -f2)}

if [ -z "$CURRENT_USER" ]; then
    echo -e "${RED}❌ Could not determine current AWS user${NC}"
    exit 1
fi

echo -e "${BLUE}Current user: ${CURRENT_USER}${NC}"
echo -e "${BLUE}Environment: ${ENVIRONMENT}${NC}"
echo -e "${BLUE}Region: ${AWS_REGION}${NC}"

# Create SQS permissions policy
echo -e "${YELLOW}📋 Creating SQS permissions policy...${NC}"

cat > sqs-permissions-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "sqs:CreateQueue",
        "sqs:DeleteQueue",
        "sqs:GetQueueAttributes",
        "sqs:GetQueueUrl",
        "sqs:ListQueues",
        "sqs:ListQueueTags",
        "sqs:TagQueue",
        "sqs:UntagQueue",
        "sqs:SetQueueAttributes"
      ],
      "Resource": [
        "arn:aws:sqs:${AWS_REGION}:*:${ENVIRONMENT}-*",
        "arn:aws:sqs:${AWS_REGION}:*:dev-*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "sqs:ListQueues"
      ],
      "Resource": "*"
    }
  ]
}
EOF

# Add the policy to the user
echo -e "${YELLOW}🔐 Adding SQS permissions to user ${CURRENT_USER}...${NC}"

if aws iam put-user-policy \
    --user-name "${CURRENT_USER}" \
    --policy-name "EventBridgeSQSAccess" \
    --policy-document file://sqs-permissions-policy.json; then
    echo -e "${GREEN}✅ SQS permissions added successfully${NC}"
else
    echo -e "${RED}❌ Failed to add SQS permissions${NC}"
    exit 1
fi

# Clean up temporary policy file
rm -f sqs-permissions-policy.json

# Test the permissions
echo -e "${YELLOW}🧪 Testing SQS permissions...${NC}"

if aws sqs list-queues --region "${AWS_REGION}" > /dev/null 2>&1; then
    echo -e "${GREEN}✅ SQS list permission works${NC}"
else
    echo -e "${YELLOW}⚠️  SQS list permission may take a moment to propagate${NC}"
fi

echo -e "\n${GREEN}🎉 SQS permissions setup completed!${NC}"
echo -e "${BLUE}You can now run the destroy script to clean up SQS queues properly.${NC}"
echo -e "${BLUE}The following permissions were added:${NC}"
echo -e "${BLUE}• Create/Delete SQS queues${NC}"
echo -e "${BLUE}• List queues and queue tags${NC}"
echo -e "${BLUE}• Manage queue attributes and tags${NC}"