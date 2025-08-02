#!/bin/bash

# Source navigation and error handling functions
source "$(dirname "$0")/step-navigation.sh" 2>/dev/null || {
    echo "Warning: Navigation functions not found"
}

source "$(dirname "$0")/error-handling.sh" 2>/dev/null || {
    echo "Warning: Error handling functions not found"
    set -e
}

echo "🔍 Step 001: Preflight Check - Validating Prerequisites"
echo "====================================================="

# Initialize error handling
SCRIPT_NAME="step-001-preflight-check"
setup_error_handling "$SCRIPT_NAME" 2>/dev/null || set -e

# Create checkpoint
create_checkpoint "$SCRIPT_NAME" "in_progress" "$SCRIPT_NAME" 2>/dev/null || true

echo -e "\n${CYAN}📋 CHECKING SYSTEM REQUIREMENTS:${NC}"

# Track failures
FAILURES=0

# Function to check command existence
check_command() {
    local cmd="$1"
    local install_hint="$2"
    
    echo -e -n "${BLUE}Checking for ${cmd}...${NC} "
    if command -v "$cmd" &>/dev/null; then
        local version=$($cmd --version 2>&1 | head -n1)
        echo -e "${GREEN}✅ Found${NC} ($version)"
        return 0
    else
        echo -e "${RED}❌ Not found${NC}"
        echo -e "   ${YELLOW}Install: ${install_hint}${NC}"
        ((FAILURES++))
        return 1
    fi
}

# Function to check AWS credentials
check_aws_credentials() {
    echo -e -n "${BLUE}Checking AWS credentials...${NC} "
    if aws sts get-caller-identity &>/dev/null; then
        local account=$(aws sts get-caller-identity --query 'Account' --output text)
        local user=$(aws sts get-caller-identity --query 'Arn' --output text | cut -d'/' -f2)
        echo -e "${GREEN}✅ Configured${NC}"
        echo -e "   ${CYAN}Account: ${account}${NC}"
        echo -e "   ${CYAN}User: ${user}${NC}"
        return 0
    else
        echo -e "${RED}❌ Not configured${NC}"
        echo -e "   ${YELLOW}Run: aws configure${NC}"
        echo -e "   ${YELLOW}Need: AWS Access Key ID, Secret Access Key, Region${NC}"
        ((FAILURES++))
        return 1
    fi
}

# Function to check AWS region
check_aws_region() {
    echo -e -n "${BLUE}Checking AWS region configuration...${NC} "
    local region=$(aws configure get region)
    if [ -n "$region" ]; then
        echo -e "${GREEN}✅ Set to ${region}${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠️  No default region set${NC}"
        echo -e "   ${YELLOW}Will use us-east-2 as default${NC}"
        echo -e "   ${YELLOW}To set: aws configure set region us-east-2${NC}"
        return 0
    fi
}

# Function to check Node.js version
check_nodejs_version() {
    echo -e -n "${BLUE}Checking Node.js version...${NC} "
    if command -v node &>/dev/null; then
        local node_version=$(node --version | cut -d'v' -f2)
        local major_version=$(echo "$node_version" | cut -d'.' -f1)
        
        if [ "$major_version" -ge 14 ]; then
            echo -e "${GREEN}✅ v${node_version} (compatible)${NC}"
            return 0
        else
            echo -e "${YELLOW}⚠️  v${node_version} (outdated)${NC}"
            echo -e "   ${YELLOW}Recommend: Node.js 14.x or higher${NC}"
            echo -e "   ${YELLOW}Lambda uses Node.js 18.x runtime${NC}"
            return 0
        fi
    else
        echo -e "${RED}❌ Not found${NC}"
        ((FAILURES++))
        return 1
    fi
}

# Function to check Terraform version
check_terraform_version() {
    echo -e -n "${BLUE}Checking Terraform version...${NC} "
    if command -v terraform &>/dev/null; then
        local tf_version=$(terraform version -json 2>/dev/null | jq -r '.terraform_version' 2>/dev/null || terraform version | head -n1 | cut -d'v' -f2 | cut -d' ' -f1)
        local major_version=$(echo "$tf_version" | cut -d'.' -f1)
        local minor_version=$(echo "$tf_version" | cut -d'.' -f2)
        
        if [ "$major_version" -eq 1 ] && [ "$minor_version" -ge 0 ]; then
            echo -e "${GREEN}✅ v${tf_version} (compatible)${NC}"
            return 0
        else
            echo -e "${YELLOW}⚠️  v${tf_version} (may have compatibility issues)${NC}"
            echo -e "   ${YELLOW}Recommend: Terraform 1.0 or higher${NC}"
            return 0
        fi
    else
        echo -e "${RED}❌ Not found${NC}"
        ((FAILURES++))
        return 1
    fi
}

# Function to check disk space
check_disk_space() {
    echo -e -n "${BLUE}Checking available disk space...${NC} "
    local available_space=$(df -BG . | awk 'NR==2 {print $4}' | sed 's/G//')
    
    if [ "$available_space" -ge 2 ]; then
        echo -e "${GREEN}✅ ${available_space}GB available${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠️  Only ${available_space}GB available${NC}"
        echo -e "   ${YELLOW}Recommend: At least 2GB free space${NC}"
        return 0
    fi
}

# Function to check IAM permissions hint
check_iam_permissions_hint() {
    echo -e "\n${CYAN}📋 IAM PERMISSIONS NEEDED:${NC}"
    echo -e "${BLUE}The following AWS permissions will be required:${NC}"
    echo -e "   • ${CYAN}EventBridge${NC}: Full access for event bus and rules"
    echo -e "   • ${CYAN}Lambda${NC}: Create and manage functions"
    echo -e "   • ${CYAN}IAM${NC}: Create roles and policies"
    echo -e "   • ${CYAN}SQS${NC}: Create and manage queues"
    echo -e "   • ${CYAN}CloudWatch Logs${NC}: Create log groups"
    echo -e "   • ${CYAN}Schemas${NC}: Create and manage schema registry"
    echo -e "\n${YELLOW}💡 Step 010 will add these permissions to your user${NC}"
}

# Run all checks
echo -e "\n${BOLD}1. Required Tools:${NC}"
check_command "aws" "https://aws.amazon.com/cli/"
check_command "terraform" "https://www.terraform.io/downloads"
check_command "jq" "https://stedolan.github.io/jq/download/"
check_command "npm" "https://nodejs.org/"
check_command "git" "https://git-scm.com/downloads"

echo -e "\n${BOLD}2. AWS Configuration:${NC}"
check_aws_credentials
check_aws_region

echo -e "\n${BOLD}3. Version Compatibility:${NC}"
check_nodejs_version
check_terraform_version

echo -e "\n${BOLD}4. System Resources:${NC}"
check_disk_space

# Show IAM permissions needed
check_iam_permissions_hint

# Summary
echo -e "\n${BLUE}════════════════════════════════════════════════════════${NC}"
if [ "$FAILURES" -eq 0 ]; then
    echo -e "${GREEN}✅ ALL PREREQUISITES MET!${NC}"
    echo -e "${CYAN}Your system is ready for EventBridge Orchestrator deployment.${NC}"
    
    # Mark step as completed
    create_checkpoint "$SCRIPT_NAME" "completed" "$SCRIPT_NAME"
    log_info "All prerequisites met - system ready for deployment" "$SCRIPT_NAME"
    
    # Show next step
    if declare -f show_next_step > /dev/null; then
        show_next_step "$(basename "$0")" "$(dirname "$0")"
    else
        echo -e "\n${CYAN}Next: Run step-010-setup-iam-permissions.sh${NC}"
    fi
else
    echo -e "${RED}❌ MISSING PREREQUISITES: ${FAILURES} issue(s) found${NC}"
    echo -e "${YELLOW}Please install missing tools before continuing.${NC}"
    echo -e "\n${CYAN}After installing prerequisites, run this script again.${NC}"
    exit 1
fi
echo -e "${BLUE}════════════════════════════════════════════════════════${NC}\n"