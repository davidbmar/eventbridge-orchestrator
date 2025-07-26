#!/bin/bash
set -e

echo "💥 Step 999: Destroy EventBridge Orchestrator"
echo "============================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Load configuration
if [ -f ".env" ]; then
    source .env
    echo -e "${GREEN}✅ Loaded configuration from .env${NC}"
else
    echo -e "${YELLOW}⚠️  No .env file found. Using defaults...${NC}"
    AWS_REGION="us-east-2"
    ENVIRONMENT="dev"
fi

# Warning prompt
echo -e "\n${RED}⚠️  WARNING: This will destroy ALL EventBridge orchestrator resources!${NC}"
echo -e "${YELLOW}This includes:${NC}"
echo -e "${BLUE}• EventBridge custom bus and rules${NC}"
echo -e "${BLUE}• Schema registry and schemas${NC}"
echo -e "${BLUE}• Lambda functions${NC}"
echo -e "${BLUE}• IAM roles and policies${NC}"
echo -e "${BLUE}• SQS dead letter queue${NC}"
echo -e "${BLUE}• CloudWatch log groups${NC}"

echo -e "\n${CYAN}Environment: ${ENVIRONMENT}${NC}"
echo -e "${CYAN}Region: ${AWS_REGION}${NC}"

# Confirmation prompt
echo -e "\n${RED}Are you ABSOLUTELY sure you want to destroy everything?${NC}"
read -p "Type 'DESTROY' in capital letters to confirm: " confirmation

if [ "$confirmation" != "DESTROY" ]; then
    echo -e "${GREEN}✅ Destruction cancelled. Nothing was destroyed.${NC}"
    exit 0
fi

echo -e "\n${YELLOW}🗑️  Starting destruction process...${NC}"

# Function to safely run commands
safe_run() {
    local description="$1"
    local command="$2"
    
    echo -e "${BLUE}${description}...${NC}"
    if eval "$command" 2>/dev/null; then
        echo -e "${GREEN}✅ ${description} completed${NC}"
    else
        echo -e "${YELLOW}⚠️  ${description} failed or resource not found${NC}"
    fi
}

# 1. Destroy Terraform-managed resources
if [ -d "terraform" ] && [ -f "terraform/.terraform.lock.hcl" ]; then
    echo -e "\n${YELLOW}🏗️  Destroying Terraform infrastructure...${NC}"
    cd terraform
    
    if terraform state list > /dev/null 2>&1; then
        echo -e "${BLUE}Found Terraform state, destroying resources...${NC}"
        terraform destroy -auto-approve
        echo -e "${GREEN}✅ Terraform destruction completed${NC}"
    else
        echo -e "${YELLOW}⚠️  No Terraform state found${NC}"
    fi
    cd ..
else
    echo -e "${YELLOW}⚠️  No Terraform state found${NC}"
fi

# 2. Delete Lambda functions
echo -e "\n${YELLOW}⚡ Destroying Lambda functions...${NC}"

LAMBDA_FUNCTIONS=(
    "dev-event-logger"
    "dev-dead-letter-processor"
    "${ENVIRONMENT}-event-logger"
    "${ENVIRONMENT}-dead-letter-processor"
)

for func in "${LAMBDA_FUNCTIONS[@]}"; do
    safe_run "Deleting Lambda function: $func" \
        "aws lambda delete-function --function-name '$func' --region '${AWS_REGION}'"
done

# 3. Delete EventBridge resources that might not be in Terraform
echo -e "\n${YELLOW}🔄 Destroying EventBridge resources...${NC}"

# Delete custom event bus if it exists
if [ "${USE_CUSTOM_BUS}" = "true" ] && [ "${EVENT_BUS_NAME}" != "default" ]; then
    # First delete all rules on the custom bus
    safe_run "Listing rules on custom bus" \
        "aws events list-rules --event-bus-name '${EVENT_BUS_NAME}' --region '${AWS_REGION}'"
    
    RULES=$(aws events list-rules --event-bus-name "${EVENT_BUS_NAME}" --region "${AWS_REGION}" --query 'Rules[].Name' --output text 2>/dev/null || echo "")
    
    if [ ! -z "$RULES" ]; then
        for rule in $RULES; do
            safe_run "Deleting rule: $rule" \
                "aws events delete-rule --name '$rule' --event-bus-name '${EVENT_BUS_NAME}' --region '${AWS_REGION}'"
        done
    fi
    
    safe_run "Deleting custom event bus: ${EVENT_BUS_NAME}" \
        "aws events delete-event-bus --name '${EVENT_BUS_NAME}' --region '${AWS_REGION}'"
fi

# 4. Delete Schema Registry and Schemas
echo -e "\n${YELLOW}📋 Destroying Schema Registry...${NC}"

REGISTRY_NAME="${ENVIRONMENT}-event-schemas"
SCHEMAS=$(aws schemas list-schemas --registry-name "${REGISTRY_NAME}" --region "${AWS_REGION}" --query 'Schemas[].SchemaName' --output text 2>/dev/null || echo "")

if [ ! -z "$SCHEMAS" ]; then
    for schema in $SCHEMAS; do
        safe_run "Deleting schema: $schema" \
            "aws schemas delete-schema --registry-name '${REGISTRY_NAME}' --schema-name '$schema' --region '${AWS_REGION}'"
    done
fi

safe_run "Deleting schema registry: ${REGISTRY_NAME}" \
    "aws schemas delete-registry --registry-name '${REGISTRY_NAME}' --region '${AWS_REGION}'"

# 5. Delete SQS Queues
echo -e "\n${YELLOW}📨 Destroying SQS queues...${NC}"

SQS_QUEUES=(
    "${ENVIRONMENT}-eventbridge-dlq"
    "dev-eventbridge-dlq"
)

for queue in "${SQS_QUEUES[@]}"; do
    QUEUE_URL=$(aws sqs get-queue-url --queue-name "$queue" --region "${AWS_REGION}" --query 'QueueUrl' --output text 2>/dev/null || echo "")
    if [ ! -z "$QUEUE_URL" ] && [ "$QUEUE_URL" != "None" ]; then
        safe_run "Deleting SQS queue: $queue" \
            "aws sqs delete-queue --queue-url '$QUEUE_URL' --region '${AWS_REGION}'"
    fi
done

# 6. Delete CloudWatch Log Groups
echo -e "\n${YELLOW}📊 Destroying CloudWatch log groups...${NC}"

LOG_GROUPS=(
    "/aws/lambda/dev-event-logger"
    "/aws/lambda/dev-dead-letter-processor"
    "/aws/lambda/${ENVIRONMENT}-event-logger"
    "/aws/lambda/${ENVIRONMENT}-dead-letter-processor"
    "/aws/events/rule/${ENVIRONMENT}-*"
)

for log_group in "${LOG_GROUPS[@]}"; do
    # List log groups matching pattern
    MATCHING_LOGS=$(aws logs describe-log-groups --log-group-name-prefix "$log_group" --region "${AWS_REGION}" --query 'logGroups[].logGroupName' --output text 2>/dev/null || echo "")
    
    if [ ! -z "$MATCHING_LOGS" ]; then
        for log in $MATCHING_LOGS; do
            safe_run "Deleting log group: $log" \
                "aws logs delete-log-group --log-group-name '$log' --region '${AWS_REGION}'"
        done
    fi
done

# 7. Delete IAM Roles and Policies (be careful with this)
echo -e "\n${YELLOW}🔐 Destroying IAM resources...${NC}"

IAM_ROLES=(
    "dev-event-publisher-role"
    "dev-event-processor-role"
    "dev-eventbridge-dlq-role"
    "${ENVIRONMENT}-event-publisher-role"
    "${ENVIRONMENT}-event-processor-role"
    "${ENVIRONMENT}-eventbridge-dlq-role"
    "EventProcessorBasicRole"
)

for role in "${IAM_ROLES[@]}"; do
    # First detach managed policies
    ATTACHED_POLICIES=$(aws iam list-attached-role-policies --role-name "$role" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
    if [ ! -z "$ATTACHED_POLICIES" ]; then
        for policy in $ATTACHED_POLICIES; do
            safe_run "Detaching policy $policy from role $role" \
                "aws iam detach-role-policy --role-name '$role' --policy-arn '$policy'"
        done
    fi
    
    # Delete inline policies
    INLINE_POLICIES=$(aws iam list-role-policies --role-name "$role" --query 'PolicyNames' --output text 2>/dev/null || echo "")
    if [ ! -z "$INLINE_POLICIES" ]; then
        for policy in $INLINE_POLICIES; do
            safe_run "Deleting inline policy $policy from role $role" \
                "aws iam delete-role-policy --role-name '$role' --policy-name '$policy'"
        done
    fi
    
    # Delete the role
    safe_run "Deleting IAM role: $role" \
        "aws iam delete-role --role-name '$role'"
done

# 8. Remove user policies we added
echo -e "\n${YELLOW}👤 Removing user policies...${NC}"

CURRENT_USER=${AWS_USER:-$(aws sts get-caller-identity --query 'Arn' --output text | cut -d'/' -f2 2>/dev/null)}
if [ ! -z "$CURRENT_USER" ]; then
    safe_run "Removing EventBridgeFullAccess policy from user $CURRENT_USER" \
        "aws iam delete-user-policy --user-name '$CURRENT_USER' --policy-name 'EventBridgeFullAccess'"
    
    safe_run "Removing EventBridgeTestPolicy from user $CURRENT_USER" \
        "aws iam delete-user-policy --user-name '$CURRENT_USER' --policy-name 'EventBridgeTestPolicy'"
fi

# 9. Clean up local files
echo -e "\n${YELLOW}🧹 Cleaning up local files...${NC}"

safe_run "Removing Terraform state files" \
    "rm -rf terraform/.terraform terraform/.terraform.lock.hcl terraform/terraform.tfstate* terraform/.terraform.tfstate.lock.info"

safe_run "Removing Lambda deployment packages" \
    "rm -f lambdas/*/*.zip"

safe_run "Removing temporary files" \
    "rm -f deployment-config.env test-results.json test-user-policy.json eventbridge-full-policy.json"

safe_run "Removing generated test files" \
    "rm -f examples/test-document-upload.json examples/test-batch-events.json"

# 10. Option to remove .env file
echo -e "\n${CYAN}Do you want to remove the .env configuration file?${NC}"
read -p "Remove .env? (y/N): " remove_env

if [[ $remove_env =~ ^[Yy]$ ]]; then
    rm -f .env .env.backup.*
    echo -e "${GREEN}✅ Removed .env file${NC}"
else
    echo -e "${BLUE}ℹ️  Kept .env file for future use${NC}"
fi

# Summary
echo -e "\n${GREEN}🎉 Destruction completed!${NC}"
echo -e "\n${BLUE}📊 Summary:${NC}"
echo -e "${BLUE}• All AWS resources have been destroyed${NC}"
echo -e "${BLUE}• Local deployment files cleaned up${NC}"
echo -e "${BLUE}• IAM policies removed from user${NC}"

if [ -f ".env" ]; then
    echo -e "${BLUE}• Configuration (.env) preserved${NC}"
    echo -e "${YELLOW}💡 You can run step-000-interactive-setup.sh to reconfigure and redeploy${NC}"
else
    echo -e "${BLUE}• Configuration (.env) removed${NC}"
    echo -e "${YELLOW}💡 You can run step-000-interactive-setup.sh to start fresh${NC}"
fi

echo -e "\n${GREEN}✨ Environment is now clean!${NC}"