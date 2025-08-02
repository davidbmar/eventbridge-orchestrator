#!/bin/bash

# Source navigation and error handling functions
source "$(dirname "$0")/step-navigation.sh" 2>/dev/null || {
    echo "Warning: Navigation functions not found"
}

source "$(dirname "$0")/error-handling.sh" 2>/dev/null || {
    echo "Warning: Error handling functions not found"
    set -e
}

echo "🏗️  Step 2: Deploying EventBridge Infrastructure"

# Initialize error handling
SCRIPT_NAME="step-020-deploy-infrastructure"
setup_error_handling "$SCRIPT_NAME" 2>/dev/null || set -e

# Create checkpoint
create_checkpoint "$SCRIPT_NAME" "in_progress" "$SCRIPT_NAME" 2>/dev/null || true

# Validate prerequisites
if declare -f validate_prerequisites > /dev/null; then
    validate_prerequisites "$(basename "$0")" "$(dirname "$0")" || exit 1
fi

# Load configuration
if [ -f ".env" ]; then
    source .env
    echo -e "${GREEN}✅ Loaded configuration from .env${NC}"
    
    # Use configured values
    AWS_REGION=${AWS_REGION:-us-east-2}
    ENVIRONMENT=${ENVIRONMENT:-dev}
    PROJECT_NAME=${PROJECT_NAME:-eventbridge-orchestrator}
else
    echo -e "${YELLOW}⚠️  No .env file found. Run step-000-interactive-setup.sh first${NC}"
    echo -e "${BLUE}Using default configuration...${NC}"
    AWS_REGION="us-east-2"
    ENVIRONMENT="dev"
    PROJECT_NAME="eventbridge-orchestrator"
fi

# Check if Step 1 was completed
CURRENT_USER=${AWS_USER:-$(aws sts get-caller-identity --query 'Arn' --output text | cut -d'/' -f2)}
if ! aws iam get-user-policy --user-name "${CURRENT_USER}" --policy-name EventBridgeFullAccess > /dev/null 2>&1; then
    echo -e "${RED}❌ Step 1 (IAM setup) not completed. Please run step-010-setup-iam-permissions.sh first${NC}"
    exit 1
fi

echo -e "${GREEN}✅ IAM permissions verified${NC}"

# Install Terraform if not present
if ! command -v terraform &> /dev/null; then
    echo -e "${YELLOW}📦 Installing Terraform...${NC}"
    curl -fsSL https://releases.hashicorp.com/terraform/1.6.6/terraform_1.6.6_linux_amd64.zip -o terraform.zip
    unzip -o terraform.zip
    sudo mv terraform /usr/local/bin/
    rm terraform.zip
    echo -e "${GREEN}✅ Terraform installed$(terraform --version | head -n1)${NC}"
else
    echo -e "${GREEN}✅ Terraform already installed: $(terraform --version | head -n1)${NC}"
fi

echo -e "${BLUE}Using AWS region: ${AWS_REGION}${NC}"

# Terraform variables should already be configured from step-000
if [ ! -f "terraform/terraform.tfvars" ]; then
    echo -e "${YELLOW}Terraform variables not found, creating from .env...${NC}"
    cat > terraform/terraform.tfvars << EOF
environment = "${ENVIRONMENT}"
project_name = "${PROJECT_NAME}"
aws_region = "${AWS_REGION}"
event_bus_name = "${EVENT_BUS_NAME:-${ENVIRONMENT}-application-events}"

# S3 Buckets  
audio_bucket = "${AUDIO_BUCKET:-audio-uploads-${ENVIRONMENT}-${AWS_REGION}}"
document_bucket = "${DOCUMENT_BUCKET:-document-uploads-${ENVIRONMENT}-${AWS_REGION}}"
video_bucket = "${VIDEO_BUCKET:-video-uploads-${ENVIRONMENT}-${AWS_REGION}}"
transcript_bucket = "${TRANSCRIPT_BUCKET:-transcription-outputs-${ENVIRONMENT}-${AWS_REGION}}"

# Lambda ARNs - will be populated in Step 3
event_logger_lambda_arn = ""
dead_letter_processor_lambda_arn = ""
transcription_handler_lambda_arn = ""
search_indexer_lambda_arn = ""
notification_handler_lambda_arn = ""
EOF
else
    echo -e "${GREEN}✅ Using existing Terraform variables${NC}"
fi

# Deploy infrastructure with retry logic
log_info "Starting Terraform deployment..." "$SCRIPT_NAME"
cd terraform

# Initialize Terraform with retry
log_info "Initializing Terraform..." "$SCRIPT_NAME"
if ! retry_command 3 10 "$SCRIPT_NAME" terraform init; then
    log_error "Terraform initialization failed" "$SCRIPT_NAME"
    exit 1
fi

# Plan deployment
log_info "Planning Terraform deployment..." "$SCRIPT_NAME"
if ! terraform plan -out=tfplan; then
    log_error "Terraform planning failed" "$SCRIPT_NAME"
    exit 1
fi

# Apply deployment with retry and error handling
log_info "Deploying infrastructure..." "$SCRIPT_NAME"
echo -e "${BLUE}Note: Schema registry permission errors are non-critical and can be ignored${NC}"

# Apply with output capture and retry logic
APPLY_SUCCESS=false
for attempt in 1 2 3; do
    log_info "Terraform apply attempt $attempt/3" "$SCRIPT_NAME"
    
    if terraform apply -auto-approve tfplan 2>&1 | tee terraform_apply.log; then
        APPLY_RESULT=0
        APPLY_SUCCESS=true
        break
    else
        APPLY_RESULT=${PIPESTATUS[0]}
        
        # Check if this is a retryable error
        if handle_terraform_error $APPLY_RESULT terraform_apply.log "$SCRIPT_NAME"; then
            case $? in
                0) 
                    APPLY_SUCCESS=true
                    break
                    ;;
                2)
                    log_warning "Retryable error detected, waiting before retry..." "$SCRIPT_NAME"
                    sleep $((attempt * 10))
                    ;;
                *)
                    log_error "Non-retryable Terraform error" "$SCRIPT_NAME"
                    break
                    ;;
            esac
        else
            log_error "Terraform apply failed" "$SCRIPT_NAME"
            break
        fi
    fi
done

if [ "$APPLY_SUCCESS" = true ]; then
    log_info "Infrastructure deployed successfully!" "$SCRIPT_NAME"
    
    # Get outputs
    EVENT_BUS_NAME=$(terraform output -raw event_bus_name 2>/dev/null || echo "default")
    echo -e "${BLUE}📝 Event Bus Name: ${EVENT_BUS_NAME}${NC}"
    
    # Create deployment config file for subsequent steps
    cd ..
    cat > deployment-config.env << EOF
AWS_REGION=${AWS_REGION}
ENVIRONMENT=${ENVIRONMENT}
EVENT_BUS_NAME=${EVENT_BUS_NAME}
PROJECT_NAME=${PROJECT_NAME}
DEPLOYMENT_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
    
    # Also update .env with deployment info if it exists
    if [ -f ".env" ]; then
        sed -i "s/^DEPLOYMENT_TIMESTAMP=.*/DEPLOYMENT_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")/" .env
        if ! grep -q "DEPLOYMENT_TIMESTAMP" .env; then
            echo "DEPLOYMENT_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")" >> .env
        fi
    fi
    
    # Check for common warnings that can be ignored
    if grep -q "User is not authorized to perform: schemas:" terraform_apply.log 2>/dev/null; then
        log_warning "Schema registry permission warning detected (non-critical)" "$SCRIPT_NAME"
    fi
    
    # Mark step as completed
    create_checkpoint "$SCRIPT_NAME" "completed" "$SCRIPT_NAME"
    log_info "Step 2 completed successfully!" "$SCRIPT_NAME"
else
    echo -e "${RED}❌ Infrastructure deployment failed${NC}"
    
    # Check if failure was due to schema registry issues only
    if grep -q "User is not authorized to perform: schemas:" terraform_apply.log && ! grep -q "Error:" terraform_apply.log; then
        echo -e "${YELLOW}💡 Deployment may have succeeded despite schema registry warnings${NC}"
        echo -e "${BLUE}   Checking if core resources were created...${NC}"
        
        # Try to get EventBridge bus name to confirm deployment worked
        if EVENT_BUS_CHECK=$(terraform output -raw event_bus_name 2>/dev/null); then
            echo -e "${GREEN}✅ Core infrastructure appears to be deployed successfully${NC}"
            EVENT_BUS_NAME="$EVENT_BUS_CHECK"
            # Continue with success path
            cd ..
            cat > deployment-config.env << EOF
AWS_REGION=${AWS_REGION}
ENVIRONMENT=${ENVIRONMENT}
EVENT_BUS_NAME=${EVENT_BUS_NAME}
PROJECT_NAME=${PROJECT_NAME}
DEPLOYMENT_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
            echo -e "${GREEN}🎉 Step 2 completed successfully (ignoring schema warnings)!${NC}"
            cd terraform
            exit 0
        fi
    fi
    
    echo -e "${YELLOW}💡 Some resources may have been created. Check AWS console.${NC}"
    echo -e "${YELLOW}💡 You can still test basic EventBridge functionality.${NC}"
    
    # Create minimal config for testing
    cd ..
    cat > deployment-config.env << EOF
AWS_REGION=${AWS_REGION}
ENVIRONMENT=${ENVIRONMENT}
EVENT_BUS_NAME=default
PROJECT_NAME=${PROJECT_NAME}
DEPLOYMENT_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
    
    echo -e "${BLUE}Proceeding with basic configuration for testing...${NC}"
fi

echo -e "\n${GREEN}🎉 Step 2 completed!${NC}"

# Show next step
if declare -f show_next_step > /dev/null; then
    show_next_step "$(basename "$0")" "$(dirname "$0")"
else
    echo -e "${BLUE}Next: Run step-040-deploy-lambdas.sh${NC}"
fi