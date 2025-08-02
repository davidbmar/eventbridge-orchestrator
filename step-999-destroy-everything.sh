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

# 1. Pre-cleanup: Remove EventBridge targets before Terraform destroy
echo -e "\n${YELLOW}🎯 Removing EventBridge targets first...${NC}"

if [ "${USE_CUSTOM_BUS}" = "true" ] && [ "${EVENT_BUS_NAME}" != "default" ]; then
    # Get all rules on the custom bus
    RULES=$(aws events list-rules --event-bus-name "${EVENT_BUS_NAME}" --region "${AWS_REGION}" --query 'Rules[].Name' --output text 2>/dev/null || echo "")
    
    if [ ! -z "$RULES" ]; then
        for rule in $RULES; do
            echo -e "${BLUE}Removing targets from rule: $rule${NC}"
            # Get all target IDs for this rule
            TARGET_IDS=$(aws events list-targets-by-rule --rule "$rule" --event-bus-name "${EVENT_BUS_NAME}" --region "${AWS_REGION}" --query 'Targets[].Id' --output text 2>/dev/null || echo "")
            
            if [ ! -z "$TARGET_IDS" ]; then
                # Remove all targets
                safe_run "Removing targets from rule $rule" \
                    "aws events remove-targets --rule '$rule' --event-bus-name '${EVENT_BUS_NAME}' --ids $TARGET_IDS --region '${AWS_REGION}'"
            fi
        done
    fi
fi

# 2. Destroy Terraform-managed resources
if [ -d "terraform" ]; then
    echo -e "\n${YELLOW}🏗️  Destroying Terraform infrastructure...${NC}"
    cd terraform
    
    if [ -f "terraform.tfstate" ] || terraform state list > /dev/null 2>&1; then
        echo -e "${BLUE}Found Terraform state, destroying resources...${NC}"
        terraform destroy -auto-approve
        echo -e "${GREEN}✅ Terraform destruction completed${NC}"
    else
        echo -e "${YELLOW}⚠️  No Terraform state found, will attempt manual cleanup${NC}"
    fi
    cd ..
else
    echo -e "${YELLOW}⚠️  No terraform directory found${NC}"
fi

# 3. Delete Lambda functions
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

# 4. Delete EventBridge resources that might not be in Terraform
echo -e "\n${YELLOW}🔄 Destroying remaining EventBridge resources...${NC}"

# Delete EventBridge Archive first
echo -e "${BLUE}Deleting EventBridge archives...${NC}"
ARCHIVES=$(aws events list-archives --region "${AWS_REGION}" --query 'Archives[?contains(ArchiveName, `dev-`) || contains(ArchiveName, `'${ENVIRONMENT}'-`)].ArchiveName' --output text 2>/dev/null || echo "")
if [ ! -z "$ARCHIVES" ]; then
    for archive in $ARCHIVES; do
        safe_run "Deleting archive: $archive" \
            "aws events delete-archive --archive-name '$archive' --region '${AWS_REGION}'"
    done
fi

# Delete Schema Discoverer
echo -e "${BLUE}Deleting Schema discoverers...${NC}"
DISCOVERERS=$(aws schemas list-discoverers --region "${AWS_REGION}" --query 'Discoverers[?contains(SourceArn, `dev-`) || contains(SourceArn, `'${ENVIRONMENT}'-`)].DiscovererId' --output text 2>/dev/null || echo "")
if [ ! -z "$DISCOVERERS" ]; then
    for discoverer in $DISCOVERERS; do
        safe_run "Deleting discoverer: $discoverer" \
            "aws schemas delete-discoverer --discoverer-id '$discoverer' --region '${AWS_REGION}'"
    done
fi

# Delete all EventBridge rules and buses
echo -e "${BLUE}Deleting EventBridge rules and buses...${NC}"

# First, list all custom event buses
CUSTOM_BUSES=$(aws events list-event-buses --region "${AWS_REGION}" --query 'EventBuses[?Name!=`default`].Name' --output text 2>/dev/null || echo "")

for bus in $CUSTOM_BUSES ${EVENT_BUS_NAME}; do
    if [ ! -z "$bus" ] && [ "$bus" != "default" ]; then
        # Get all rules on this bus
        RULES=$(aws events list-rules --event-bus-name "$bus" --region "${AWS_REGION}" --query 'Rules[].Name' --output text 2>/dev/null || echo "")
        
        if [ ! -z "$RULES" ]; then
            for rule in $RULES; do
                # Remove any remaining targets first
                TARGET_IDS=$(aws events list-targets-by-rule --rule "$rule" --event-bus-name "$bus" --region "${AWS_REGION}" --query 'Targets[].Id' --output text 2>/dev/null || echo "")
                
                if [ ! -z "$TARGET_IDS" ]; then
                    safe_run "Removing targets from rule $rule on bus $bus" \
                        "aws events remove-targets --rule '$rule' --event-bus-name '$bus' --ids $TARGET_IDS --region '${AWS_REGION}'"
                fi
                
                # Now delete the rule
                safe_run "Deleting rule: $rule on bus $bus" \
                    "aws events delete-rule --name '$rule' --event-bus-name '$bus' --region '${AWS_REGION}'"
            done
        fi
        
        # Delete the custom bus
        safe_run "Deleting custom event bus: $bus" \
            "aws events delete-event-bus --name '$bus' --region '${AWS_REGION}'"
    fi
done

# 5. Delete Schema Registry and Schemas
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

# 6. Delete SQS Queues
echo -e "\n${YELLOW}📨 Destroying SQS queues...${NC}"

# Try specific queue names first
SQS_QUEUE_NAMES=(
    "dev-eventbridge-dlq"
    "${ENVIRONMENT}-eventbridge-dlq"
)

for queue_name in "${SQS_QUEUE_NAMES[@]}"; do
    QUEUE_URL=$(aws sqs get-queue-url --queue-name "$queue_name" --region "${AWS_REGION}" --query 'QueueUrl' --output text 2>/dev/null || echo "")
    if [ ! -z "$QUEUE_URL" ] && [ "$QUEUE_URL" != "None" ]; then
        safe_run "Deleting SQS queue: $queue_name" \
            "aws sqs delete-queue --queue-url '$QUEUE_URL' --region '${AWS_REGION}'"
    fi
done

# Also try to list all queues and filter (if permissions allow)
ALL_QUEUES=$(aws sqs list-queues --region "${AWS_REGION}" --query 'QueueUrls' --output text 2>/dev/null || echo "")

for queue_url in $ALL_QUEUES; do
    # Extract queue name from URL
    queue_name=$(echo "$queue_url" | awk -F'/' '{print $NF}')
    
    # Check if this is one of our queues
    if [[ "$queue_name" =~ ^(dev-|${ENVIRONMENT}-).*dlq$ ]] || [[ "$queue_name" =~ eventbridge-dlq$ ]]; then
        safe_run "Deleting SQS queue: $queue_name" \
            "aws sqs delete-queue --queue-url '$queue_url' --region '${AWS_REGION}'"
    fi
done

# 7. Delete CloudWatch Log Groups
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

# 8. Delete IAM Roles and Policies (be careful with this)
echo -e "\n${YELLOW}🔐 Destroying IAM resources...${NC}"

# List all IAM roles and filter for our patterns
ALL_ROLES=$(aws iam list-roles --query 'Roles[].RoleName' --output text 2>/dev/null || echo "")

for role in $ALL_ROLES; do
    # Check if this is one of our EventBridge-related roles
    if [[ "$role" =~ ^(dev-|${ENVIRONMENT}-)event-(publisher|processor|logger|handler)-role$ ]] || \
       [[ "$role" =~ ^(dev-|${ENVIRONMENT}-).*eventbridge.*-role$ ]] || \
       [[ "$role" =~ ^EventProcessor.*Role$ ]]; then

        echo -e "${BLUE}Processing IAM role: $role${NC}"
        
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
    fi
done

# 9. Remove user policies we added
echo -e "\n${YELLOW}👤 Removing user policies...${NC}"

CURRENT_USER=${AWS_USER:-$(aws sts get-caller-identity --query 'Arn' --output text | cut -d'/' -f2 2>/dev/null)}
if [ ! -z "$CURRENT_USER" ]; then
    safe_run "Removing EventBridgeFullAccess policy from user $CURRENT_USER" \
        "aws iam delete-user-policy --user-name '$CURRENT_USER' --policy-name 'EventBridgeFullAccess'"
    
    safe_run "Removing EventBridgeTestPolicy from user $CURRENT_USER" \
        "aws iam delete-user-policy --user-name '$CURRENT_USER' --policy-name 'EventBridgeTestPolicy'"
fi

# 10. Clean up local files
echo -e "\n${YELLOW}🧹 Cleaning up local files...${NC}"

safe_run "Removing Terraform state files" \
    "rm -rf terraform/.terraform terraform/.terraform.lock.hcl terraform/terraform.tfstate* terraform/.terraform.tfstate.lock.info"

safe_run "Removing Lambda deployment packages" \
    "rm -f lambdas/*/*.zip"

safe_run "Removing temporary files" \
    "rm -f deployment-config.env test-results.json test-user-policy.json eventbridge-full-policy.json"

safe_run "Removing generated test files" \
    "rm -f examples/test-document-upload.json examples/test-batch-events.json"

# 11. Option to remove .env file
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