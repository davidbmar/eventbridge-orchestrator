#!/bin/bash

# Step Navigation Functions for EventBridge Orchestrator
# This file provides navigation helpers for the deployment scripts

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Step descriptions
declare -A STEP_DESCRIPTIONS=(
    ["step-000-interactive-setup.sh"]="🔧 Interactive setup and configuration"
    ["step-010-setup-iam-permissions.sh"]="🔐 Configure IAM permissions for EventBridge"
    ["step-015-add-sqs-permissions.sh"]="📨 Add SQS permissions for dead letter queue"
    ["step-020-deploy-infrastructure.sh"]="🏗️  Deploy EventBridge infrastructure with Terraform"
    ["step-040-deploy-lambdas.sh"]="⚡ Deploy Lambda functions for event processing"
    ["step-050-test-events.sh"]="🧪 Test event processing and validate deployment"
    ["step-998-pre-destroy-cleanup.sh"]="🧹 Remove EventBridge dependencies before Terraform destroy"
    ["step-999-destroy-everything.sh"]="💥 Complete infrastructure teardown with Terraform destroy"
)

# Function to detect the next step based on current script
detect_next_step() {
    local current_script="$1"
    local script_dir="${2:-$(dirname "$0")}"
    
    # Extract step number from current script
    local current_num=$(echo "$current_script" | grep -oE 'step-[0-9]+' | grep -oE '[0-9]+')
    
    if [ -z "$current_num" ]; then
        return 1
    fi
    
    # Find the next step file
    local next_step=""
    local next_num=""
    
    # Handle special case: after step 050, next is destroy workflow
    if [ "$current_num" = "050" ]; then
        if [ -f "$script_dir/step-998-pre-destroy-cleanup.sh" ]; then
            echo "$script_dir/step-998-pre-destroy-cleanup.sh"
            return 0
        fi
    fi
    
    # Handle destroy workflow: 998 → 999
    if [ "$current_num" = "998" ]; then
        if [ -f "$script_dir/step-999-destroy-everything.sh" ]; then
            echo "$script_dir/step-999-destroy-everything.sh"
            return 0
        fi
    fi
    
    # Look for the next sequential step (regular deployment flow)
    for step_file in $(ls "$script_dir"/step-*.sh 2>/dev/null | sort); do
        local step_num=$(echo "$step_file" | grep -oE 'step-[0-9]+' | grep -oE '[0-9]+')
        
        # Only process if we found a valid step number
        if [ -n "$step_num" ] && [ "$step_num" -gt 0 ] 2>/dev/null; then
            if [ "$step_num" -gt "$current_num" ] 2>/dev/null && [ "$step_num" -lt 900 ] 2>/dev/null; then
                if [ -z "$next_num" ] || [ "$step_num" -lt "$next_num" ] 2>/dev/null; then
                    next_num="$step_num"
                    next_step="$step_file"
                fi
            fi
        fi
    done
    
    echo "$next_step"
}

# Function to show next step with description
show_next_step() {
    local current_script="$1"
    local script_dir="${2:-$(dirname "$0")}"
    
    echo -e "\n${BLUE}════════════════════════════════════════════════════════════════${NC}"
    
    local next_step_file=$(detect_next_step "$current_script" "$script_dir")
    
    if [ -n "$next_step_file" ]; then
        local next_step_name=$(basename "$next_step_file")
        local description="${STEP_DESCRIPTIONS[$next_step_name]:-📋 Continue deployment process}"
        
        echo -e "${GREEN}✅ Current step completed successfully!${NC}"
        echo -e ""
        echo -e "${BOLD}${CYAN}Next Step:${NC} ${YELLOW}$next_step_name${NC}"
        echo -e "${BOLD}${CYAN}Purpose:${NC}   $description"
        echo -e ""
        echo -e "${BOLD}${CYAN}To continue:${NC}"
        echo -e "   ${YELLOW}./$next_step_name${NC}"
        echo -e ""
        echo -e "${CYAN}💡 Or run all remaining steps:${NC}"
        echo -e "   ${YELLOW}./deploy.sh${NC}"
        
    else
        # Check if we're at the end of the sequence
        local current_num=$(echo "$current_script" | grep -oE 'step-[0-9]+' | grep -oE '[0-9]+')
        if [ "$current_num" = "050" ]; then
            echo -e "${GREEN}🎉 Deployment sequence completed!${NC}"
            echo -e ""
            echo -e "${BOLD}${CYAN}Your EventBridge Orchestrator is now ready!${NC}"
            echo -e ""
            echo -e "${CYAN}Available commands:${NC}"
            echo -e "   ${YELLOW}./step-050-test-events.sh${NC}  - Run additional tests"
            echo -e "   ${YELLOW}./step-998-pre-destroy-cleanup.sh${NC}  - Start destroy workflow"
            echo -e ""
            echo -e "${CYAN}📖 Check the README.md for usage examples and next steps${NC}"
        elif [ "$current_num" = "999" ]; then
            echo -e "${GREEN}🎉 Complete teardown finished!${NC}"
            echo -e ""
            echo -e "${BOLD}${CYAN}EventBridge Orchestrator has been completely removed!${NC}"
            echo -e ""
            echo -e "${CYAN}Next steps:${NC}"
            echo -e "   ${YELLOW}./step-000-interactive-setup.sh${NC}  - Start fresh deployment"
            echo -e "   ${YELLOW}git pull${NC}  - Update to latest version"
            echo -e ""
            echo -e "${CYAN}🧹 Environment is now clean and ready for redeployment${NC}"
        else
            echo -e "${YELLOW}⚠️  No next step detected${NC}"
            echo -e ""
            echo -e "${CYAN}Available options:${NC}"
            echo -e "   ${YELLOW}./deploy.sh${NC}  - Run full deployment"
            echo -e "   ${YELLOW}ls step-*.sh${NC}  - See all available steps"
        fi
    fi
    
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}\n"
}

# Function to show all available steps
show_all_steps() {
    local script_dir="${1:-$(dirname "$0")}"
    
    echo -e "\n${BOLD}${CYAN}EventBridge Orchestrator - Available Steps:${NC}\n"
    
    echo -e "${BOLD}${GREEN}📚 DEPLOYMENT STEPS:${NC}"
    for step_file in $(ls "$script_dir"/step-0*.sh 2>/dev/null | sort); do
        local step_name=$(basename "$step_file")
        local description="${STEP_DESCRIPTIONS[$step_name]:-📋 Script description not available}"
        
        echo -e "${YELLOW}$step_name${NC}"
        echo -e "   $description"
        echo ""
    done
    
    echo -e "${BOLD}${RED}🗑️  DESTROY STEPS:${NC}"
    for step_file in $(ls "$script_dir"/step-9*.sh 2>/dev/null | sort); do
        local step_name=$(basename "$step_file")
        local description="${STEP_DESCRIPTIONS[$step_name]:-📋 Script description not available}"
        
        echo -e "${YELLOW}$step_name${NC}"
        echo -e "   $description"
        echo ""
    done
    
    echo -e "${BOLD}${CYAN}💡 DESTROY WORKFLOW:${NC}"
    echo -e "${BLUE}1. ./step-998-pre-destroy-cleanup.sh  (Remove dependencies)${NC}"
    echo -e "${BLUE}2. ./step-999-destroy-everything.sh   (Complete teardown)${NC}"
}

# Function to validate step sequence
validate_prerequisites() {
    local current_script="$1"
    local script_dir="${2:-$(dirname "$0")}"
    
    # Extract current step number
    local current_num=$(echo "$current_script" | grep -oE 'step-[0-9]+' | grep -oE '[0-9]+')
    
    if [ -z "$current_num" ]; then
        return 0  # Not a numbered step, skip validation
    fi
    
    # Special cases
    if [ "$current_num" = "000" ] || [ "$current_num" = "999" ]; then
        return 0  # Setup and destroy can be run anytime
    fi
    
    # Check if .env exists (created by step-000)
    if [ ! -f ".env" ] && [ "$current_num" != "000" ]; then
        echo -e "\n${YELLOW}⚠️  Missing configuration file (.env)${NC}"
        echo -e "${CYAN}Please run step-000-interactive-setup.sh first${NC}\n"
        return 1
    fi
    
    return 0
}