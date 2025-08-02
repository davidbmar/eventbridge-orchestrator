#!/bin/bash

# Source navigation and error handling functions
source "$(dirname "$0")/step-navigation.sh" 2>/dev/null || {
    echo "Warning: Navigation functions not found"
}

source "$(dirname "$0")/error-handling.sh" 2>/dev/null || {
    echo "Warning: Error handling functions not found"
}

# Initialize error handling
SCRIPT_NAME="step-010-setup-iam-permissions"
setup_error_handling "$SCRIPT_NAME" 2>/dev/null || set -e

echo "🔐 Step 1: Setting up IAM permissions for EventBridge testing"

# Create checkpoint
create_checkpoint "$SCRIPT_NAME" "in_progress" "$SCRIPT_NAME" 2>/dev/null || true

# Check prerequisites
if ! check_deployment_prerequisites "$SCRIPT_NAME"; then
    log_error "Prerequisites not met" "$SCRIPT_NAME"
    exit 1
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

# Test permissions with retry
log_info "Testing EventBridge permissions..." "$SCRIPT_NAME"
if retry_command 3 5 "$SCRIPT_NAME" aws events describe-event-bus --name default --region us-east-2; then
    log_info "EventBridge permissions verified successfully" "$SCRIPT_NAME"
else
    log_error "EventBridge permissions test failed after retries" "$SCRIPT_NAME"
    exit 1
fi

# Clean up temp file
rm eventbridge-full-policy.json

# Mark step as completed
create_checkpoint "$SCRIPT_NAME" "completed" "$SCRIPT_NAME"
log_info "Step 1 completed successfully!" "$SCRIPT_NAME"

# Show next step
if declare -f show_next_step > /dev/null; then
    show_next_step "$(basename "$0")" "$(dirname "$0")"
else
    echo -e "${BLUE}Next: Run step-015-add-sqs-permissions.sh${NC}"
fi