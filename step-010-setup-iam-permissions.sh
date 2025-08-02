#!/bin/bash
set -e

# Source navigation functions
source "$(dirname "$0")/step-navigation.sh" 2>/dev/null || {
    echo "Warning: Navigation functions not found"
}

echo "🔐 Step 1: Setting up IAM permissions for EventBridge testing"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Validate prerequisites
if declare -f validate_prerequisites > /dev/null; then
    validate_prerequisites "$(basename "$0")" "$(dirname "$0")" || exit 1
fi

# Load configuration
if [ -f ".env" ]; then
    source .env
    echo -e "${GREEN}✅ Loaded configuration from .env${NC}"
else
    echo -e "${YELLOW}⚠️  No .env file found. Run step-000-interactive-setup.sh first${NC}"
    echo -e "${BLUE}Using default configuration...${NC}"
fi

# Get current user
CURRENT_USER=${AWS_USER:-$(aws sts get-caller-identity --query 'Arn' --output text | cut -d'/' -f2)}
echo -e "${BLUE}Current IAM user: ${CURRENT_USER}${NC}"

# Create comprehensive EventBridge policy
echo -e "${YELLOW}Creating EventBridge IAM policy...${NC}"

cat > eventbridge-full-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "events:*",
                "schemas:*",
                "sqs:CreateQueue",
                "sqs:DeleteQueue",
                "sqs:GetQueueAttributes",
                "sqs:GetQueueUrl",
                "sqs:ListQueues",
                "sqs:ListQueueTags",
                "sqs:SendMessage",
                "sqs:ReceiveMessage",
                "sqs:DeleteMessage",
                "sqs:TagQueue",
                "sqs:UntagQueue",
                "sqs:SetQueueAttributes",
                "iam:CreateRole",
                "iam:DeleteRole",
                "iam:PutRolePolicy",
                "iam:DeleteRolePolicy",
                "iam:AttachRolePolicy",
                "iam:DetachRolePolicy",
                "iam:ListAttachedRolePolicies",
                "iam:ListRolePolicies",
                "iam:PassRole",
                "iam:ListRoles",
                "iam:GetRole",
                "iam:TagRole",
                "lambda:CreateFunction",
                "lambda:GetFunction",
                "lambda:AddPermission",
                "lambda:InvokeFunction",
                "lambda:TagResource",
                "cloudwatch:PutMetricData",
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "*"
        }
    ]
}
EOF

# Apply the policy to current user
echo -e "${YELLOW}Applying policy to user: ${CURRENT_USER}${NC}"
aws iam put-user-policy \
    --user-name "${CURRENT_USER}" \
    --policy-name "EventBridgeFullAccess" \
    --policy-document file://eventbridge-full-policy.json

echo -e "${GREEN}✅ IAM permissions configured successfully!${NC}"

# Wait for IAM propagation
echo -e "${YELLOW}Waiting 10 seconds for IAM changes to propagate...${NC}"
sleep 10

# Test permissions
echo -e "${BLUE}Testing EventBridge permissions...${NC}"
aws events describe-event-bus --name default --region us-east-2 > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ EventBridge permissions working!${NC}"
else
    echo -e "${RED}❌ EventBridge permissions test failed${NC}"
    exit 1
fi

# Clean up temp file
rm eventbridge-full-policy.json

echo -e "${GREEN}🎉 Step 1 completed successfully!${NC}"

# Show next step
if declare -f show_next_step > /dev/null; then
    show_next_step "$(basename "$0")" "$(dirname "$0")"
else
    echo -e "${BLUE}Next: Run step-015-add-sqs-permissions.sh${NC}"
fi