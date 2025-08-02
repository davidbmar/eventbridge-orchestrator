#!/bin/bash

# Common error handling functions for EventBridge Orchestrator scripts
# Source this file in other scripts: source "$(dirname "$0")/error-handling.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Global variables for error tracking
ERROR_COUNT=0
WARNING_COUNT=0
DEPLOYMENT_STATE_DIR=".deployment-state"

# Ensure deployment state directory and log files exist immediately
if [ ! -d "$DEPLOYMENT_STATE_DIR" ]; then
    mkdir -p "$DEPLOYMENT_STATE_DIR" 2>/dev/null || {
        echo "Warning: Could not create deployment state directory"
        # Fallback to current directory for logs
        DEPLOYMENT_STATE_DIR="."
    }
fi

# Initialize log files if they don't exist
touch "${DEPLOYMENT_STATE_DIR}/deployment.log" 2>/dev/null || true
touch "${DEPLOYMENT_STATE_DIR}/errors.log" 2>/dev/null || true
touch "${DEPLOYMENT_STATE_DIR}/warnings.log" 2>/dev/null || true
touch "${DEPLOYMENT_STATE_DIR}/checkpoints.log" 2>/dev/null || true

# Function to log errors with timestamp
log_error() {
    local message="$1"
    local script_name="$2"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    echo -e "${RED}❌ ERROR: ${message}${NC}" >&2
    echo "${timestamp} ERROR [${script_name:-unknown}]: ${message}" >> "${DEPLOYMENT_STATE_DIR}/errors.log" 2>/dev/null || true
    ((ERROR_COUNT++))
}

# Function to log warnings with timestamp
log_warning() {
    local message="$1"
    local script_name="$2"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    echo -e "${YELLOW}⚠️  WARNING: ${message}${NC}"
    echo "${timestamp} WARNING [${script_name:-unknown}]: ${message}" >> "${DEPLOYMENT_STATE_DIR}/warnings.log" 2>/dev/null || true
    ((WARNING_COUNT++))
}

# Function to log info messages
log_info() {
    local message="$1"
    local script_name="$2"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    echo -e "${BLUE}ℹ️  ${message}${NC}"
    echo "${timestamp} INFO [${script_name:-unknown}]: ${message}" >> "${DEPLOYMENT_STATE_DIR}/deployment.log" 2>/dev/null || true
}

# Function to check if a command exists
check_command_exists() {
    local cmd="$1"
    local install_hint="$2"
    local script_name="$3"
    
    if ! command -v "$cmd" &>/dev/null; then
        log_error "Required command '$cmd' not found. ${install_hint}" "$script_name"
        return 1
    fi
    return 0
}

# Function to check if AWS credentials are configured
check_aws_credentials() {
    local script_name="$1"
    
    if ! aws sts get-caller-identity &>/dev/null; then
        log_error "AWS credentials not configured. Run 'aws configure' first." "$script_name"
        return 1
    fi
    return 0
}

# Function to check if IAM permissions exist
check_iam_permission() {
    local policy_name="$1"
    local user_name="$2"
    local script_name="$3"
    
    if ! aws iam get-user-policy --user-name "$user_name" --policy-name "$policy_name" &>/dev/null; then
        log_error "IAM policy '$policy_name' not found for user '$user_name'. Run step-010 first." "$script_name"
        return 1
    fi
    return 0
}

# Function to validate environment variables
validate_env_var() {
    local var_name="$1"
    local var_value="$2"
    local script_name="$3"
    
    if [ -z "$var_value" ]; then
        log_error "Required environment variable '$var_name' is not set." "$script_name"
        return 1
    fi
    return 0
}

# Function to check if a file exists
check_file_exists() {
    local file_path="$1"
    local script_name="$2"
    
    if [ ! -f "$file_path" ]; then
        log_error "Required file '$file_path' not found." "$script_name"
        return 1
    fi
    return 0
}

# Function to retry a command with exponential backoff
retry_command() {
    local max_attempts="$1"
    local delay="$2"
    local script_name="$3"
    shift 3
    local cmd=("$@")
    
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        log_info "Attempt $attempt/$max_attempts: ${cmd[*]}" "$script_name"
        
        if "${cmd[@]}"; then
            return 0
        fi
        
        if [ $attempt -lt $max_attempts ]; then
            log_warning "Command failed, retrying in ${delay}s..." "$script_name"
            sleep "$delay"
            delay=$((delay * 2))  # Exponential backoff
        fi
        
        ((attempt++))
    done
    
    log_error "Command failed after $max_attempts attempts: ${cmd[*]}" "$script_name"
    return 1
}

# Function to check AWS service availability
check_aws_service() {
    local service="$1"
    local region="$2"
    local script_name="$3"
    
    case "$service" in
        "events")
            if ! aws events list-event-buses --region "$region" &>/dev/null; then
                log_error "EventBridge service not available in region $region" "$script_name"
                return 1
            fi
            ;;
        "lambda")
            if ! aws lambda list-functions --region "$region" &>/dev/null; then
                log_error "Lambda service not available in region $region" "$script_name"
                return 1
            fi
            ;;
        "iam")
            if ! aws iam list-users &>/dev/null; then
                log_error "IAM service not available" "$script_name"
                return 1
            fi
            ;;
        *)
            log_warning "Unknown service '$service' for availability check" "$script_name"
            ;;
    esac
    return 0
}

# Function to handle Terraform errors gracefully
handle_terraform_error() {
    local exit_code="$1"
    local log_file="$2"
    local script_name="$3"
    
    if [ "$exit_code" -ne 0 ]; then
        # Check for specific known issues
        if grep -q "User is not authorized to perform: schemas:" "$log_file" 2>/dev/null; then
            log_warning "Schema registry permission error detected (non-critical)" "$script_name"
            
            # Check if core resources were still created
            if terraform output event_bus_name &>/dev/null; then
                log_info "Core infrastructure appears to be deployed despite schema warnings" "$script_name"
                return 0  # Treat as success
            fi
        fi
        
        if grep -q "already exists" "$log_file" 2>/dev/null; then
            log_warning "Some resources already exist (possibly from previous deployment)" "$script_name"
            return 0  # Treat as success for idempotency
        fi
        
        if grep -q "timeout" "$log_file" 2>/dev/null; then
            log_error "Terraform operation timed out. AWS might be experiencing delays." "$script_name"
            return 2  # Special code for retry
        fi
        
        log_error "Terraform operation failed. Check $log_file for details." "$script_name"
        return 1
    fi
    
    return 0
}

# Function to check deployment prerequisites
check_deployment_prerequisites() {
    local script_name="$1"
    local required_tools=("aws" "terraform" "jq")
    local failed=0
    
    log_info "Checking deployment prerequisites..." "$script_name"
    
    # Check required tools
    for tool in "${required_tools[@]}"; do
        if ! check_command_exists "$tool" "Please install $tool" "$script_name"; then
            failed=1
        fi
    done
    
    # Check AWS credentials
    if ! check_aws_credentials "$script_name"; then
        failed=1
    fi
    
    # Check if running as root (not recommended)
    if [ "$EUID" -eq 0 ]; then
        log_warning "Running as root is not recommended for security reasons" "$script_name"
    fi
    
    return $failed
}

# Function to create deployment state checkpoint
create_checkpoint() {
    local step_name="$1"
    local status="$2"  # pending, in_progress, completed, failed
    local script_name="$3"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    echo "${timestamp} ${step_name} ${status}" >> "${DEPLOYMENT_STATE_DIR}/checkpoints.log" 2>/dev/null || true
    echo "${status}" > "${DEPLOYMENT_STATE_DIR}/${step_name}.status" 2>/dev/null || true
    
    log_info "Checkpoint: ${step_name} -> ${status}" "$script_name"
}

# Function to check if step was completed
is_step_completed() {
    local step_name="$1"
    local status_file="${DEPLOYMENT_STATE_DIR}/${step_name}.status"
    
    if [ -f "$status_file" ]; then
        local status=$(cat "$status_file" 2>/dev/null)
        [ "$status" = "completed" ]
    else
        return 1
    fi
}

# Function to show deployment summary
show_deployment_summary() {
    local script_name="$1"
    
    echo -e "\n${BOLD}=== DEPLOYMENT SUMMARY ===${NC}"
    echo -e "${BLUE}Errors: ${ERROR_COUNT}${NC}"
    echo -e "${YELLOW}Warnings: ${WARNING_COUNT}${NC}"
    
    if [ -f "${DEPLOYMENT_STATE_DIR}/checkpoints.log" ]; then
        echo -e "\n${BOLD}Completed Steps:${NC}"
        grep "completed" "${DEPLOYMENT_STATE_DIR}/checkpoints.log" | while read -r line; do
            echo -e "${GREEN}✅ $line${NC}"
        done
    fi
    
    if [ $ERROR_COUNT -gt 0 ]; then
        echo -e "\n${RED}Recent errors (see ${DEPLOYMENT_STATE_DIR}/errors.log for full details):${NC}"
        tail -n 5 "${DEPLOYMENT_STATE_DIR}/errors.log" 2>/dev/null || echo "No error log found"
    fi
}

# Function to clean up deployment state (for fresh starts)
clean_deployment_state() {
    local script_name="$1"
    
    if [ -d "$DEPLOYMENT_STATE_DIR" ]; then
        log_info "Cleaning previous deployment state..." "$script_name"
        rm -rf "$DEPLOYMENT_STATE_DIR"
        mkdir -p "$DEPLOYMENT_STATE_DIR"
    fi
}

# Trap function for cleanup on script exit
cleanup_on_exit() {
    local exit_code=$?
    local script_name="$1"
    
    # Only log error if it's actually an error (non-zero exit and not from normal completion)
    if [ $exit_code -ne 0 ] && [ "${BASH_COMMAND}" != "exit 0" ]; then
        log_error "Script exited with code $exit_code" "$script_name"
        show_deployment_summary "$script_name"
    fi
}

# Function to set up error handling for a script
setup_error_handling() {
    local script_name="$1"
    
    # Enable basic error handling without problematic traps
    set -e
    set -o pipefail
    
    # Don't set error traps - they cause false positives
    # Scripts should handle their own error checking
    
    log_info "Error handling initialized for $script_name" "$script_name"
}

# Separate function for actual errors
cleanup_on_error() {
    local script_name="$1"
    local exit_code="$2"
    
    # Only log if it's a real error (not success)
    if [ "$exit_code" -ne 0 ]; then
        log_error "Script failed with code $exit_code" "$script_name"
        show_deployment_summary "$script_name"
    fi
}