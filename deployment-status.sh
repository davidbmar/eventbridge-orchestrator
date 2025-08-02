#!/bin/bash

# EventBridge Orchestrator - Deployment Status Checker
# Quick overview of deployment progress and system health

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

DEPLOYMENT_STATE_DIR=".deployment-state"

echo -e "${BOLD}🔍 EventBridge Orchestrator - Deployment Status${NC}"
echo "================================================"

# Check if deployment state directory exists
if [ ! -d "$DEPLOYMENT_STATE_DIR" ]; then
    echo -e "${YELLOW}⚠️  No deployment state found${NC}"
    echo -e "${BLUE}Run ./step-001-preflight-check.sh to begin deployment${NC}"
    exit 0
fi

# Function to get step status
get_step_status() {
    local step_name="$1"
    local status_file="${DEPLOYMENT_STATE_DIR}/${step_name}.status"
    
    if [ -f "$status_file" ]; then
        cat "$status_file" 2>/dev/null || echo "unknown"
    else
        echo "not_started"
    fi
}

# Function to display status with icon
display_status() {
    local step_name="$1"
    local display_name="$2"
    local status=$(get_step_status "$step_name")
    
    case "$status" in
        "completed")
            echo -e "${GREEN}✅ $display_name${NC}"
            ;;
        "in_progress")
            echo -e "${YELLOW}🔄 $display_name${NC}"
            ;;
        "failed")
            echo -e "${RED}❌ $display_name${NC}"
            ;;
        "not_started")
            echo -e "${BLUE}⭕ $display_name${NC}"
            ;;
        *)
            echo -e "${CYAN}❓ $display_name (unknown)${NC}"
            ;;
    esac
}

# Show deployment steps status
echo -e "\n${BOLD}📋 Deployment Steps:${NC}"
display_status "step-001-preflight-check" "Preflight Check"
display_status "step-010-setup-iam-permissions" "IAM Permissions"
display_status "step-020-deploy-infrastructure" "Infrastructure Deployment"
display_status "step-040-deploy-lambdas" "Lambda Functions"
display_status "step-050-test-events" "Event Validation"

# Check overall deployment status
overall_status=$(get_step_status "deploy-all")
if [ "$overall_status" = "completed" ]; then
    echo -e "\n${GREEN}🎉 Complete Deployment: SUCCESSFUL${NC}"
elif [ "$overall_status" = "in_progress" ]; then
    echo -e "\n${YELLOW}🔄 Complete Deployment: IN PROGRESS${NC}"
else
    echo -e "\n${BLUE}⏳ Complete Deployment: PENDING${NC}"
fi

# Show error count if errors exist
if [ -f "${DEPLOYMENT_STATE_DIR}/errors.log" ]; then
    error_count=$(wc -l < "${DEPLOYMENT_STATE_DIR}/errors.log" 2>/dev/null || echo "0")
    if [ "$error_count" -gt 0 ]; then
        echo -e "\n${RED}⚠️  Total Errors: $error_count${NC}"
        echo -e "${BLUE}Latest errors:${NC}"
        tail -n 3 "${DEPLOYMENT_STATE_DIR}/errors.log" 2>/dev/null | while read -r line; do
            echo -e "   ${RED}• $line${NC}"
        done
    fi
fi

# Show warning count if warnings exist
if [ -f "${DEPLOYMENT_STATE_DIR}/warnings.log" ]; then
    warning_count=$(wc -l < "${DEPLOYMENT_STATE_DIR}/warnings.log" 2>/dev/null || echo "0")
    if [ "$warning_count" -gt 0 ]; then
        echo -e "\n${YELLOW}⚠️  Total Warnings: $warning_count${NC}"
    fi
fi

# Check AWS resources status if infrastructure is deployed
infrastructure_status=$(get_step_status "step-020-deploy-infrastructure")
if [ "$infrastructure_status" = "completed" ]; then
    echo -e "\n${BOLD}☁️  AWS Resources Status:${NC}"
    
    # Load deployment config
    if [ -f "deployment-config.env" ]; then
        source deployment-config.env
        
        # Check EventBridge bus
        if aws events describe-event-bus --name "${EVENT_BUS_NAME}" --region "${AWS_REGION}" &>/dev/null; then
            echo -e "${GREEN}✅ EventBridge Bus: ${EVENT_BUS_NAME}${NC}"
        else
            echo -e "${RED}❌ EventBridge Bus: Not found${NC}"
        fi
        
        # Check Lambda functions
        if [ -n "${EVENT_LOGGER_ARN}" ]; then
            if aws lambda get-function --function-name "${EVENT_LOGGER_ARN}" --region "${AWS_REGION}" &>/dev/null; then
                echo -e "${GREEN}✅ Event Logger Lambda: Active${NC}"
            else
                echo -e "${RED}❌ Event Logger Lambda: Not found${NC}"
            fi
        fi
        
        if [ -n "${DLQ_PROCESSOR_ARN}" ]; then
            if aws lambda get-function --function-name "${DLQ_PROCESSOR_ARN}" --region "${AWS_REGION}" &>/dev/null; then
                echo -e "${GREEN}✅ DLQ Processor Lambda: Active${NC}"
            else
                echo -e "${RED}❌ DLQ Processor Lambda: Not found${NC}"
            fi
        fi
    else
        echo -e "${YELLOW}⚠️  No deployment config found${NC}"
    fi
fi

# Show next recommended action
echo -e "\n${BOLD}🎯 Next Actions:${NC}"

# Determine what to do next based on current state
preflight_status=$(get_step_status "step-001-preflight-check")
iam_status=$(get_step_status "step-010-setup-iam-permissions")
infra_status=$(get_step_status "step-020-deploy-infrastructure")
lambda_status=$(get_step_status "step-040-deploy-lambdas")
test_status=$(get_step_status "step-050-test-events")

if [ "$preflight_status" != "completed" ]; then
    echo -e "${BLUE}• Run preflight check: ./step-001-preflight-check.sh${NC}"
elif [ "$iam_status" != "completed" ]; then
    echo -e "${BLUE}• Setup IAM permissions: ./step-010-setup-iam-permissions.sh${NC}"
elif [ "$infra_status" != "completed" ]; then
    echo -e "${BLUE}• Deploy infrastructure: ./step-020-deploy-infrastructure.sh${NC}"
elif [ "$lambda_status" != "completed" ]; then
    echo -e "${BLUE}• Deploy Lambda functions: ./step-040-deploy-lambdas.sh${NC}"
elif [ "$test_status" != "completed" ]; then
    echo -e "${BLUE}• Test event processing: ./step-050-test-events.sh${NC}"
else
    echo -e "${GREEN}• Deployment complete! Test with: ./step-050-test-events.sh${NC}"
    echo -e "${BLUE}• Or run full deployment: ./deploy-all.sh${NC}"
fi

# Show logs location
echo -e "\n${CYAN}📁 Logs and state files: .deployment-state/${NC}"
if [ -d "$DEPLOYMENT_STATE_DIR" ]; then
    echo -e "${BLUE}Files:${NC}"
    ls -la "$DEPLOYMENT_STATE_DIR" 2>/dev/null | grep -v "^total" | while read -r line; do
        echo -e "   ${CYAN}$line${NC}"
    done
fi

echo ""