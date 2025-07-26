#!/bin/bash
set -e

echo "🏗️  Step 2: Deploying EventBridge Infrastructure"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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

# Deploy infrastructure
echo -e "${BLUE}📋 Initializing Terraform...${NC}"
cd terraform
terraform init

echo -e "${BLUE}📋 Planning deployment...${NC}"
terraform plan

echo -e "${YELLOW}🚀 Deploying infrastructure...${NC}"
terraform apply -auto-approve

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Infrastructure deployed successfully!${NC}"
    
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
    
    echo -e "${GREEN}🎉 Step 2 completed successfully!${NC}"
    echo -e "${BLUE}Next: Run step-040-deploy-lambdas.sh${NC}"
else
    echo -e "${RED}❌ Infrastructure deployment failed${NC}"
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