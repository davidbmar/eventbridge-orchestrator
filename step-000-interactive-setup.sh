#!/bin/bash
set -e

echo "🚀 EventBridge Orchestrator - Interactive Setup"
echo "=============================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to prompt for input with default
prompt_with_default() {
    local prompt="$1"
    local default="$2"
    local varname="$3"
    
    echo -e "${CYAN}${prompt}${NC}"
    if [ ! -z "$default" ]; then
        echo -e "${YELLOW}  [Press Enter for default: ${default}]${NC}"
    fi
    read -p "  > " input
    
    if [ -z "$input" ] && [ ! -z "$default" ]; then
        input="$default"
    fi
    
    eval "$varname='$input'"
}

# Function to prompt yes/no
prompt_yes_no() {
    local prompt="$1"
    local default="$2"
    local varname="$3"
    
    while true; do
        echo -e "${CYAN}${prompt} (y/n)${NC}"
        if [ ! -z "$default" ]; then
            echo -e "${YELLOW}  [Press Enter for default: ${default}]${NC}"
        fi
        read -p "  > " yn
        
        if [ -z "$yn" ] && [ ! -z "$default" ]; then
            yn="$default"
        fi
        
        case $yn in
            [Yy]* ) eval "$varname=true"; break;;
            [Nn]* ) eval "$varname=false"; break;;
            * ) echo -e "${RED}Please answer yes or no.${NC}";;
        esac
    done
}

echo -e "\n${BLUE}This script will help you configure the EventBridge Orchestrator.${NC}"
echo -e "${BLUE}All settings will be saved to .env for future use.${NC}\n"

# Check if .env already exists
if [ -f ".env" ]; then
    echo -e "${YELLOW}⚠️  Found existing .env file!${NC}"
    prompt_yes_no "Do you want to backup and recreate it?" "n" RECREATE_ENV
    if [ "$RECREATE_ENV" = "true" ]; then
        cp .env .env.backup.$(date +%Y%m%d_%H%M%S)
        echo -e "${GREEN}✅ Backed up existing .env${NC}"
    else
        echo -e "${BLUE}Loading existing configuration...${NC}"
        source .env
        echo -e "${GREEN}✅ Loaded existing .env${NC}"
    fi
else
    RECREATE_ENV=true
fi

# Get current AWS info
echo -e "\n${BLUE}📋 Checking AWS Configuration...${NC}"
CURRENT_USER=$(aws sts get-caller-identity --query 'Arn' --output text | cut -d'/' -f2 2>/dev/null || echo "")
CURRENT_ACCOUNT=$(aws sts get-caller-identity --query 'Account' --output text 2>/dev/null || echo "")
CURRENT_REGION=$(aws configure get region 2>/dev/null || echo "")

if [ -z "$CURRENT_USER" ]; then
    echo -e "${RED}❌ AWS CLI not configured or no permissions${NC}"
    echo -e "${YELLOW}Please run 'aws configure' first${NC}"
    exit 1
fi

echo -e "${GREEN}✅ AWS User: ${CURRENT_USER}${NC}"
echo -e "${GREEN}✅ Account: ${CURRENT_ACCOUNT}${NC}"
echo -e "${GREEN}✅ Current Region: ${CURRENT_REGION}${NC}"

# Environment Configuration
echo -e "\n${BLUE}🌍 Environment Configuration${NC}"
echo -e "Configure the deployment environment and naming."

if [ "$RECREATE_ENV" = "true" ] || [ -z "$ENVIRONMENT" ]; then
    prompt_with_default "Environment name (dev/staging/prod):" "${ENVIRONMENT:-dev}" ENVIRONMENT
fi

if [ "$RECREATE_ENV" = "true" ] || [ -z "$PROJECT_NAME" ]; then
    prompt_with_default "Project name:" "${PROJECT_NAME:-eventbridge-orchestrator}" PROJECT_NAME
fi

if [ "$RECREATE_ENV" = "true" ] || [ -z "$AWS_REGION" ]; then
    prompt_with_default "AWS Region:" "${AWS_REGION:-$CURRENT_REGION}" AWS_REGION
fi

# S3 Configuration
echo -e "\n${BLUE}🪣 S3 Bucket Configuration${NC}"
echo -e "Configure S3 buckets for different file types."

BUCKET_SUFFIX="${ENVIRONMENT}-${AWS_REGION}"

if [ "$RECREATE_ENV" = "true" ] || [ -z "$AUDIO_BUCKET" ]; then
    prompt_with_default "Audio uploads bucket:" "${AUDIO_BUCKET:-audio-uploads-${BUCKET_SUFFIX}}" AUDIO_BUCKET
fi

if [ "$RECREATE_ENV" = "true" ] || [ -z "$DOCUMENT_BUCKET" ]; then
    prompt_with_default "Document uploads bucket:" "${DOCUMENT_BUCKET:-document-uploads-${BUCKET_SUFFIX}}" DOCUMENT_BUCKET
fi

if [ "$RECREATE_ENV" = "true" ] || [ -z "$VIDEO_BUCKET" ]; then
    prompt_with_default "Video uploads bucket:" "${VIDEO_BUCKET:-video-uploads-${BUCKET_SUFFIX}}" VIDEO_BUCKET
fi

if [ "$RECREATE_ENV" = "true" ] || [ -z "$TRANSCRIPT_BUCKET" ]; then
    prompt_with_default "Transcription outputs bucket:" "${TRANSCRIPT_BUCKET:-transcription-outputs-${BUCKET_SUFFIX}}" TRANSCRIPT_BUCKET
fi

# EventBridge Configuration
echo -e "\n${BLUE}🔄 EventBridge Configuration${NC}"

if [ "$RECREATE_ENV" = "true" ] || [ -z "$EVENT_BUS_NAME" ]; then
    prompt_with_default "Custom EventBridge bus name:" "${EVENT_BUS_NAME:-${ENVIRONMENT}-application-events}" EVENT_BUS_NAME
fi

if [ "$RECREATE_ENV" = "true" ] || [ -z "$USE_CUSTOM_BUS" ]; then
    prompt_yes_no "Use custom EventBridge bus? (recommended)" "${USE_CUSTOM_BUS:-y}" USE_CUSTOM_BUS
fi

if [ "$USE_CUSTOM_BUS" = "false" ]; then
    EVENT_BUS_NAME="default"
fi

# Lambda Configuration
echo -e "\n${BLUE}⚡ Lambda Configuration${NC}"

if [ "$RECREATE_ENV" = "true" ] || [ -z "$DEPLOY_LAMBDAS" ]; then
    prompt_yes_no "Deploy Lambda functions (event-logger, dead-letter-processor)?" "${DEPLOY_LAMBDAS:-y}" DEPLOY_LAMBDAS
fi

if [ "$DEPLOY_LAMBDAS" = "true" ]; then
    if [ "$RECREATE_ENV" = "true" ] || [ -z "$LAMBDA_MEMORY_SIZE" ]; then
        prompt_with_default "Lambda memory size (MB):" "${LAMBDA_MEMORY_SIZE:-256}" LAMBDA_MEMORY_SIZE
    fi
    
    if [ "$RECREATE_ENV" = "true" ] || [ -z "$LAMBDA_TIMEOUT" ]; then
        prompt_with_default "Lambda timeout (seconds):" "${LAMBDA_TIMEOUT:-60}" LAMBDA_TIMEOUT
    fi
fi

# Monitoring Configuration
echo -e "\n${BLUE}📊 Monitoring Configuration${NC}"

if [ "$RECREATE_ENV" = "true" ] || [ -z "$ENABLE_MONITORING" ]; then
    prompt_yes_no "Enable detailed monitoring and logging?" "${ENABLE_MONITORING:-y}" ENABLE_MONITORING
fi

if [ "$ENABLE_MONITORING" = "true" ]; then
    if [ "$RECREATE_ENV" = "true" ] || [ -z "$LOG_RETENTION_DAYS" ]; then
        prompt_with_default "CloudWatch log retention (days):" "${LOG_RETENTION_DAYS:-7}" LOG_RETENTION_DAYS
    fi
fi

# Alert Configuration
if [ "$RECREATE_ENV" = "true" ] || [ -z "$ENABLE_ALERTS" ]; then
    prompt_yes_no "Enable SNS alerts for failures?" "${ENABLE_ALERTS:-n}" ENABLE_ALERTS
fi

if [ "$ENABLE_ALERTS" = "true" ]; then
    if [ "$RECREATE_ENV" = "true" ] || [ -z "$ALERT_EMAIL" ]; then
        prompt_with_default "Alert email address:" "${ALERT_EMAIL:-}" ALERT_EMAIL
    fi
fi

# Advanced Configuration
echo -e "\n${BLUE}⚙️  Advanced Configuration${NC}"

if [ "$RECREATE_ENV" = "true" ] || [ -z "$CREATE_S3_BUCKETS" ]; then
    prompt_yes_no "Auto-create S3 buckets if they don't exist?" "${CREATE_S3_BUCKETS:-y}" CREATE_S3_BUCKETS
fi

if [ "$RECREATE_ENV" = "true" ] || [ -z "$ENABLE_ENCRYPTION" ]; then
    prompt_yes_no "Enable encryption for SQS and S3?" "${ENABLE_ENCRYPTION:-y}" ENABLE_ENCRYPTION
fi

# Generate .env file
echo -e "\n${YELLOW}📝 Generating .env file...${NC}"

cat > .env << EOF
# EventBridge Orchestrator Configuration
# Generated on $(date -u +"%Y-%m-%d %H:%M:%S UTC")

# Environment
ENVIRONMENT=${ENVIRONMENT}
PROJECT_NAME=${PROJECT_NAME}
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT=${CURRENT_ACCOUNT}
AWS_USER=${CURRENT_USER}

# S3 Buckets
AUDIO_BUCKET=${AUDIO_BUCKET}
DOCUMENT_BUCKET=${DOCUMENT_BUCKET}
VIDEO_BUCKET=${VIDEO_BUCKET}
TRANSCRIPT_BUCKET=${TRANSCRIPT_BUCKET}
CREATE_S3_BUCKETS=${CREATE_S3_BUCKETS}

# EventBridge
EVENT_BUS_NAME=${EVENT_BUS_NAME}
USE_CUSTOM_BUS=${USE_CUSTOM_BUS}

# Lambda Functions
DEPLOY_LAMBDAS=${DEPLOY_LAMBDAS}
LAMBDA_MEMORY_SIZE=${LAMBDA_MEMORY_SIZE:-256}
LAMBDA_TIMEOUT=${LAMBDA_TIMEOUT:-60}

# Monitoring
ENABLE_MONITORING=${ENABLE_MONITORING}
LOG_RETENTION_DAYS=${LOG_RETENTION_DAYS:-7}

# Alerts
ENABLE_ALERTS=${ENABLE_ALERTS}
ALERT_EMAIL=${ALERT_EMAIL:-}

# Security
ENABLE_ENCRYPTION=${ENABLE_ENCRYPTION}

# Runtime Variables (populated by deployment scripts)
EVENT_LOGGER_ARN=
DLQ_PROCESSOR_ARN=
EVENT_PROCESSOR_ROLE_ARN=
DEPLOYMENT_TIMESTAMP=
TERRAFORM_STATE_BUCKET=
EOF

echo -e "${GREEN}✅ Configuration saved to .env${NC}"

# Update Terraform variables
echo -e "${YELLOW}📝 Updating Terraform configuration...${NC}"

cat > terraform/terraform.tfvars << EOF
# Auto-generated from .env configuration
environment = "${ENVIRONMENT}"
project_name = "${PROJECT_NAME}"
aws_region = "${AWS_REGION}"

# S3 Buckets
audio_bucket = "${AUDIO_BUCKET}"
document_bucket = "${DOCUMENT_BUCKET}"
video_bucket = "${VIDEO_BUCKET}"
transcript_bucket = "${TRANSCRIPT_BUCKET}"

# Lambda ARNs (populated by deployment scripts)
event_logger_lambda_arn = ""
dead_letter_processor_lambda_arn = ""
transcription_handler_lambda_arn = ""
search_indexer_lambda_arn = ""
notification_handler_lambda_arn = ""
EOF

echo -e "${GREEN}✅ Terraform variables updated${NC}"

# Show summary
echo -e "\n${BLUE}📋 Configuration Summary${NC}"
echo -e "========================"
echo -e "${CYAN}Environment:${NC} ${ENVIRONMENT}"
echo -e "${CYAN}Project:${NC} ${PROJECT_NAME}"
echo -e "${CYAN}Region:${NC} ${AWS_REGION}"
echo -e "${CYAN}Event Bus:${NC} ${EVENT_BUS_NAME}"
echo -e "${CYAN}Deploy Lambdas:${NC} ${DEPLOY_LAMBDAS}"
echo -e "${CYAN}Enable Monitoring:${NC} ${ENABLE_MONITORING}"
echo -e "${CYAN}Enable Alerts:${NC} ${ENABLE_ALERTS}"

# Next steps
echo -e "\n${GREEN}🎉 Interactive setup completed!${NC}"
echo -e "\n${YELLOW}📋 Next Steps:${NC}"
echo -e "${BLUE}1. Run: ./step-010-setup-iam-permissions.sh${NC}"
echo -e "${BLUE}2. Run: ./step-020-deploy-infrastructure.sh${NC}"
echo -e "${BLUE}3. Run: ./step-040-deploy-lambdas.sh${NC}"
echo -e "${BLUE}4. Run: ./step-050-test-events.sh${NC}"

echo -e "\n${YELLOW}💡 Pro Tips:${NC}"
echo -e "${BLUE}• Your configuration is saved in .env${NC}"
echo -e "${BLUE}• You can re-run this script to update settings${NC}"
echo -e "${BLUE}• All subsequent scripts will use these settings${NC}"
echo -e "${BLUE}• Check README-SETUP.md for detailed documentation${NC}"

# Offer to run next step
echo -e "\n${CYAN}Would you like to run step 1 (IAM setup) now?${NC}"
prompt_yes_no "Continue with step-010-setup-iam-permissions.sh?" "y" RUN_STEP_1

if [ "$RUN_STEP_1" = "true" ]; then
    echo -e "\n${YELLOW}🚀 Running step 1...${NC}"
    ./step-010-setup-iam-permissions.sh
fi