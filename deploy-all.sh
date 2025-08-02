#!/bin/bash

# EventBridge Orchestrator - Complete Deployment Script
# This script runs all deployment steps in sequence with error handling and recovery

# Source error handling functions
source "$(dirname "$0")/error-handling.sh" 2>/dev/null || {
    echo "Error: error-handling.sh not found. Please ensure all files are present."
    exit 1
}

# Initialize error handling
SCRIPT_NAME="deploy-all"
setup_error_handling "$SCRIPT_NAME"

echo "🚀 EventBridge Orchestrator - Complete Deployment"
echo "================================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Configuration
FRESH_START=false
SKIP_PREFLIGHT=false
AUTO_APPROVE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --fresh-start)
            FRESH_START=true
            shift
            ;;
        --skip-preflight)
            SKIP_PREFLIGHT=true
            shift
            ;;
        --auto-approve)
            AUTO_APPROVE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --fresh-start     Clean deployment state and start fresh"
            echo "  --skip-preflight  Skip preflight checks (not recommended)"
            echo "  --auto-approve    Don't prompt for confirmation between steps"
            echo "  --help, -h        Show this help message"
            echo ""
            echo "Steps executed:"
            echo "  1. Preflight checks (step-001)"
            echo "  2. IAM permissions setup (step-010)"
            echo "  3. Infrastructure deployment (step-020)"
            echo "  4. Lambda deployment (step-040)"
            echo "  5. Event validation (step-050)"
            echo ""
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Function to prompt for continuation
prompt_continue() {
    local step_name="$1"
    local description="$2"
    
    if [ "$AUTO_APPROVE" = true ]; then
        log_info "Auto-approve enabled, continuing with $step_name" "$SCRIPT_NAME"
        return 0
    fi
    
    echo -e "\n${CYAN}Next: ${step_name}${NC}"
    echo -e "${BLUE}$description${NC}"
    echo -e "${YELLOW}Continue? (y/n/s=skip): ${NC}"
    read -r response
    
    case "$response" in
        [yY]|[yY][eE][sS]|"")
            return 0
            ;;
        [sS]|[sS][kK][iI][pP])
            log_warning "Skipping $step_name" "$SCRIPT_NAME"
            return 2
            ;;
        *)
            log_info "Deployment cancelled by user" "$SCRIPT_NAME"
            exit 0
            ;;
    esac
}

# Function to run a deployment step
run_step() {
    local step_script="$1"
    local step_name="$2"
    local required="$3"  # true/false
    
    if [ ! -f "$step_script" ]; then
        if [ "$required" = true ]; then
            log_error "Required step script not found: $step_script" "$SCRIPT_NAME"
            return 1
        else
            log_warning "Optional step script not found: $step_script" "$SCRIPT_NAME"
            return 2
        fi
    fi
    
    # Check if step was already completed
    local step_base=$(basename "$step_script" .sh)
    if is_step_completed "$step_base"; then
        log_info "$step_name already completed, skipping" "$SCRIPT_NAME"
        return 0
    fi
    
    log_info "Starting $step_name..." "$SCRIPT_NAME"
    create_checkpoint "$step_base" "in_progress" "$SCRIPT_NAME"
    
    echo -e "\n${BOLD}=== $step_name ===${NC}"
    
    # Run the step script with output capture
    if bash "$step_script" 2>&1 | tee ".deployment-state/${step_base}.log"; then
        create_checkpoint "$step_base" "completed" "$SCRIPT_NAME"
        log_info "$step_name completed successfully" "$SCRIPT_NAME"
        return 0
    else
        local exit_code=${PIPESTATUS[0]}
        create_checkpoint "$step_base" "failed" "$SCRIPT_NAME"
        log_error "$step_name failed with exit code $exit_code" "$SCRIPT_NAME"
        return $exit_code
    fi
}

# Function to check if deployment can continue after failure
can_continue_after_failure() {
    local failed_step="$1"
    
    case "$failed_step" in
        "step-001-preflight-check")
            echo -e "${RED}Prerequisites not met. Cannot continue.${NC}"
            return 1
            ;;
        "step-010-setup-iam-permissions")
            echo -e "${RED}IAM permissions required. Cannot continue.${NC}"
            return 1
            ;;
        "step-020-deploy-infrastructure")
            echo -e "${YELLOW}Infrastructure deployment failed, but you can try Lambda deployment.${NC}"
            echo -e "${BLUE}Some features may not work without complete infrastructure.${NC}"
            prompt_continue "Continue anyway?" "Deploy Lambdas and test basic functionality"
            return $?
            ;;
        *)
            echo -e "${YELLOW}Step failed but deployment can continue with reduced functionality.${NC}"
            prompt_continue "Continue anyway?" "Skip failed step and continue"
            return $?
            ;;
    esac
}

# Main deployment flow
main() {
    log_info "Starting EventBridge Orchestrator deployment" "$SCRIPT_NAME"
    
    # Clean state if requested
    if [ "$FRESH_START" = true ]; then
        echo -e "${YELLOW}🧹 Cleaning previous deployment state...${NC}"
        clean_deployment_state "$SCRIPT_NAME"
    fi
    
    # Show current working directory and validate
    echo -e "\n${BLUE}Working directory: $(pwd)${NC}"
    echo -e "${BLUE}Repository status:${NC}"
    if git status --porcelain &>/dev/null; then
        git status --short 2>/dev/null || echo "Not in a git repository"
    fi
    
    # Step 1: Preflight checks
    if [ "$SKIP_PREFLIGHT" != true ]; then
        if ! prompt_continue "Preflight Check" "Validate system prerequisites and requirements"; then
            case $? in
                2) log_warning "Skipping preflight checks" "$SCRIPT_NAME" ;;
                *) exit 0 ;;
            esac
        else
            if ! run_step "./step-001-preflight-check.sh" "Preflight Check" true; then
                can_continue_after_failure "step-001-preflight-check" || exit 1
            fi
        fi
    else
        log_warning "Skipping preflight checks (not recommended)" "$SCRIPT_NAME"
    fi
    
    # Step 2: IAM permissions
    if ! prompt_continue "IAM Setup" "Configure required AWS IAM permissions"; then
        case $? in
            2) log_warning "Skipping IAM setup" "$SCRIPT_NAME" ;;
            *) exit 0 ;;
        esac
    else
        if ! run_step "./step-010-setup-iam-permissions.sh" "IAM Permissions Setup" true; then
            can_continue_after_failure "step-010-setup-iam-permissions" || exit 1
        fi
    fi
    
    # Step 3: Infrastructure deployment
    if ! prompt_continue "Infrastructure Deployment" "Deploy EventBridge infrastructure with Terraform"; then
        case $? in
            2) log_warning "Skipping infrastructure deployment" "$SCRIPT_NAME" ;;
            *) exit 0 ;;
        esac
    else
        if ! run_step "./step-020-deploy-infrastructure.sh" "Infrastructure Deployment" true; then
            can_continue_after_failure "step-020-deploy-infrastructure" || exit 1
        fi
    fi
    
    # Step 4: Lambda deployment
    if ! prompt_continue "Lambda Deployment" "Deploy Lambda functions for event processing"; then
        case $? in
            2) log_warning "Skipping Lambda deployment" "$SCRIPT_NAME" ;;
            *) exit 0 ;;
        esac
    else
        if ! run_step "./step-040-deploy-lambdas.sh" "Lambda Deployment" false; then
            can_continue_after_failure "step-040-deploy-lambdas" || true
        fi
    fi
    
    # Step 5: Event validation
    if ! prompt_continue "Event Validation" "Test EventBridge functionality and event flow"; then
        case $? in
            2) log_warning "Skipping event validation" "$SCRIPT_NAME" ;;
            *) exit 0 ;;
        esac
    else
        if ! run_step "./step-050-test-events.sh" "Event Validation" false; then
            log_warning "Event validation failed, but deployment may still be functional" "$SCRIPT_NAME"
        fi
    fi
    
    # Deployment summary
    echo -e "\n${BOLD}=== DEPLOYMENT COMPLETE ===${NC}"
    show_deployment_summary "$SCRIPT_NAME"
    
    # Show next steps
    echo -e "\n${CYAN}🎉 EventBridge Orchestrator deployment finished!${NC}"
    echo -e "\n${BOLD}Next Steps:${NC}"
    echo -e "${BLUE}• Test your deployment: ./step-050-test-events.sh${NC}"
    echo -e "${BLUE}• View deployment logs: ls -la .deployment-state/${NC}"
    echo -e "${BLUE}• To destroy: ./step-998-pre-destroy-cleanup.sh && ./step-999-destroy-everything.sh${NC}"
    
    # Check if any critical components failed
    if [ $ERROR_COUNT -gt 0 ]; then
        echo -e "\n${YELLOW}⚠️  Deployment completed with $ERROR_COUNT error(s).${NC}"
        echo -e "${BLUE}Check .deployment-state/errors.log for details.${NC}"
        exit 1
    else
        echo -e "\n${GREEN}✅ All deployment steps completed successfully!${NC}"
        create_checkpoint "deploy-all" "completed" "$SCRIPT_NAME"
        exit 0
    fi
}

# Check if script is being sourced or executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi