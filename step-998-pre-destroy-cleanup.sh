#!/bin/bash
set -e

echo "🧹 Step 998: Pre-Destroy Cleanup - Removing EventBridge Dependencies"
echo "=================================================================="

echo -e "\n${CYAN}📋 SCRIPT PURPOSE:${NC}"
echo -e "${BLUE}This script handles AWS API-level dependency cleanup that prevents Terraform destroy from working.${NC}"
echo -e "${BLUE}EventBridge has strict dependency rules - you cannot delete rules that have active targets.${NC}"
echo -e "${BLUE}Terraform often fails to handle these dependencies correctly, causing destroy to hang or fail.${NC}"

echo -e "\n${CYAN}🔄 WHAT THIS SCRIPT DOES:${NC}"
echo -e "${BLUE}Phase 1: Removes EventBridge rule targets (Lambda, SQS, SNS)${NC}"
echo -e "${BLUE}Phase 2: Deletes Lambda functions that were targets${NC}"
echo -e "${BLUE}Phase 3: Removes EventBridge rules (now safe to delete)${NC}"
echo -e "${BLUE}Phase 4: Cleans up SQS dead letter queues${NC}"

echo -e "\n${CYAN}🎯 WHY RUN THIS SEPARATELY:${NC}"
echo -e "${BLUE}• AWS API requires specific deletion order for EventBridge resources${NC}"
echo -e "${BLUE}• Terraform dependency resolution sometimes fails with EventBridge${NC}"
echo -e "${BLUE}• Manual AWS CLI calls are more reliable for complex dependencies${NC}"
echo -e "${BLUE}• Prevents Terraform state corruption from partial failures${NC}"

echo -e "\n${CYAN}⏭️  NEXT STEP AFTER THIS:${NC}"
echo -e "${BLUE}Run step-999-destroy-everything.sh to complete infrastructure teardown${NC}"

# Warning and confirmation
echo -e "\n${RED}⚠️  WARNING: This script will remove AWS resources!${NC}"
echo -e "${YELLOW}Resources to be removed:${NC}"
echo -e "${BLUE}• EventBridge rule targets (Lambda functions, SQS queues)${NC}"
echo -e "${BLUE}• Lambda functions (event-logger, dead-letter-processor)${NC}"
echo -e "${BLUE}• EventBridge rules${NC}"
echo -e "${BLUE}• SQS dead letter queues${NC}"
echo -e "\n${CYAN}💡 This script is safe to run multiple times and will skip resources that don't exist.${NC}"

# User confirmation
echo -e "\n${YELLOW}Do you want to proceed with pre-destroy cleanup?${NC}"
read -p "Type 'yes' to continue or any other key to cancel: " confirmation

if [ "$confirmation" != "yes" ]; then
    echo -e "${GREEN}✅ Pre-destroy cleanup cancelled.${NC}"
    exit 0
fi

echo -e "\n${YELLOW}🚀 Starting pre-destroy cleanup...${NC}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Load configuration with robust fallbacks
if [ -f ".env" ]; then
    source .env
    echo -e "${GREEN}✅ Loaded configuration from .env${NC}"
elif [ -f "deployment-config.env" ]; then
    source deployment-config.env
    echo -e "${GREEN}✅ Loaded configuration from deployment-config.env${NC}"
else
    echo -e "${YELLOW}⚠️  No configuration file found. Using defaults...${NC}"
fi

# Set robust defaults
AWS_REGION="${AWS_REGION:-us-east-2}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
PROJECT_NAME="${PROJECT_NAME:-eventbridge-orchestrator}"

# Detect event bus names to clean up
POTENTIAL_BUS_NAMES=(
    "dev-application-events"
    "${ENVIRONMENT}-application-events"
    "${EVENT_BUS_NAME}"
    "dbm-eventbridge"
    "dbm-eventbridge-dev"
)

echo -e "\n${CYAN}Configuration:${NC}"
echo -e "${BLUE}• AWS Region: ${AWS_REGION}${NC}"
echo -e "${BLUE}• Environment: ${ENVIRONMENT}${NC}"
echo -e "${BLUE}• Project: ${PROJECT_NAME}${NC}"

# Function to safely run commands
safe_run() {
    local description="$1"
    local command="$2"
    
    echo -e "${BLUE}${description}...${NC}"
    if eval "$command" 2>/dev/null; then
        echo -e "${GREEN}✅ ${description} completed${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠️  ${description} failed or resource not found${NC}"
        return 1
    fi
}

# Function to remove all targets from a rule
remove_rule_targets() {
    local rule_name="$1"
    local bus_name="$2"
    
    echo -e "${BLUE}Checking targets for rule: $rule_name on bus: $bus_name${NC}"
    
    # Get all target IDs for this rule
    local target_ids
    target_ids=$(aws events list-targets-by-rule \
        --rule "$rule_name" \
        --event-bus-name "$bus_name" \
        --region "$AWS_REGION" \
        --query 'Targets[].Id' \
        --output text 2>/dev/null || echo "")
    
    if [ ! -z "$target_ids" ] && [ "$target_ids" != "None" ]; then
        echo -e "${YELLOW}Found targets: $target_ids${NC}"
        
        # Remove all targets
        safe_run "Removing targets ($target_ids) from rule $rule_name" \
            "aws events remove-targets --rule '$rule_name' --event-bus-name '$bus_name' --ids $target_ids --region '$AWS_REGION'"
    else
        echo -e "${GREEN}✅ No targets found for rule $rule_name${NC}"
    fi
}

echo -e "\n${YELLOW}🎯 Step 1: Removing EventBridge Rule Targets${NC}"
echo "=============================================="

# Process all potential event buses
for bus_name in "${POTENTIAL_BUS_NAMES[@]}"; do
    if [ ! -z "$bus_name" ] && [ "$bus_name" != "default" ]; then
        echo -e "\n${CYAN}Processing event bus: $bus_name${NC}"
        
        # Check if bus exists
        if aws events describe-event-bus --name "$bus_name" --region "$AWS_REGION" >/dev/null 2>&1; then
            echo -e "${GREEN}✅ Event bus exists: $bus_name${NC}"
            
            # Get all rules on this bus
            local rules
            rules=$(aws events list-rules \
                --event-bus-name "$bus_name" \
                --region "$AWS_REGION" \
                --query 'Rules[].Name' \
                --output text 2>/dev/null || echo "")
            
            if [ ! -z "$rules" ] && [ "$rules" != "None" ]; then
                echo -e "${BLUE}Found rules: $rules${NC}"
                
                # Remove targets from each rule
                for rule in $rules; do
                    # Skip AWS managed rules
                    if [[ ! "$rule" =~ ^(Events-Archive|Schemas-events) ]]; then
                        remove_rule_targets "$rule" "$bus_name"
                    else
                        echo -e "${CYAN}ℹ️  Skipping AWS managed rule: $rule${NC}"
                    fi
                done
            else
                echo -e "${GREEN}✅ No custom rules found on bus $bus_name${NC}"
            fi
        else
            echo -e "${YELLOW}⚠️  Event bus not found: $bus_name${NC}"
        fi
    fi
done

echo -e "\n${YELLOW}⚡ Step 2: Removing Lambda Functions${NC}"
echo "===================================="

# List of potential Lambda functions to clean up
LAMBDA_FUNCTIONS=(
    "dev-event-logger"
    "dev-dead-letter-processor"
    "${ENVIRONMENT}-event-logger"
    "${ENVIRONMENT}-dead-letter-processor"
)

for func_name in "${LAMBDA_FUNCTIONS[@]}"; do
    if [ ! -z "$func_name" ]; then
        safe_run "Deleting Lambda function: $func_name" \
            "aws lambda delete-function --function-name '$func_name' --region '$AWS_REGION'"
    fi
done

echo -e "\n${YELLOW}🗑️  Step 3: Removing EventBridge Rules${NC}"
echo "======================================="

# Now remove rules (after targets are gone)
for bus_name in "${POTENTIAL_BUS_NAMES[@]}"; do
    if [ ! -z "$bus_name" ] && [ "$bus_name" != "default" ]; then
        echo -e "\n${CYAN}Removing rules from bus: $bus_name${NC}"
        
        if aws events describe-event-bus --name "$bus_name" --region "$AWS_REGION" >/dev/null 2>&1; then
            # Get all rules again
            local rules
            rules=$(aws events list-rules \
                --event-bus-name "$bus_name" \
                --region "$AWS_REGION" \
                --query 'Rules[].Name' \
                --output text 2>/dev/null || echo "")
            
            if [ ! -z "$rules" ] && [ "$rules" != "None" ]; then
                for rule in $rules; do
                    # Skip AWS managed rules
                    if [[ ! "$rule" =~ ^(Events-Archive|Schemas-events) ]]; then
                        safe_run "Deleting rule: $rule" \
                            "aws events delete-rule --name '$rule' --event-bus-name '$bus_name' --region '$AWS_REGION'"
                    fi
                done
            fi
        fi
    fi
done

echo -e "\n${YELLOW}📨 Step 4: Cleaning up SQS Queues${NC}"
echo "=================================="

# Clean up SQS DLQ
DLQ_NAMES=(
    "dev-eventbridge-dlq"
    "${ENVIRONMENT}-eventbridge-dlq"
)

for queue_name in "${DLQ_NAMES[@]}"; do
    if [ ! -z "$queue_name" ]; then
        # Get queue URL
        local queue_url
        queue_url=$(aws sqs get-queue-url --queue-name "$queue_name" --region "$AWS_REGION" --query 'QueueUrl' --output text 2>/dev/null || echo "")
        
        if [ ! -z "$queue_url" ] && [ "$queue_url" != "None" ]; then
            safe_run "Deleting SQS queue: $queue_name" \
                "aws sqs delete-queue --queue-url '$queue_url' --region '$AWS_REGION'"
        fi
    fi
done

echo -e "\n${GREEN}🎉 Pre-destroy cleanup completed!${NC}"
echo -e "\n${CYAN}Summary of actions:${NC}"
echo -e "${BLUE}• Removed EventBridge rule targets${NC}"
echo -e "${BLUE}• Deleted Lambda functions${NC}"
echo -e "${BLUE}• Removed EventBridge rules${NC}"
echo -e "${BLUE}• Cleaned up SQS queues${NC}"

echo -e "\n${YELLOW}💡 Next steps:${NC}"
echo -e "${BLUE}1. Run step-999-destroy-everything.sh to complete infrastructure cleanup${NC}"
echo -e "${BLUE}2. Or run 'terraform destroy' manually in the terraform directory${NC}"

echo -e "\n${GREEN}✨ EventBridge dependencies cleared for safe Terraform destruction!${NC}"
echo -e "${CYAN}📋 You can now safely run the main destroy script without dependency issues.${NC}"