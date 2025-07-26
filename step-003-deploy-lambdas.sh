#!/bin/bash
set -e

echo "⚡ Step 3: Deploying Lambda Functions"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Load deployment config
if [ ! -f deployment-config.env ]; then
    echo -e "${RED}❌ deployment-config.env not found. Please run step-002 first.${NC}"
    exit 1
fi

source deployment-config.env
echo -e "${BLUE}Using AWS region: ${AWS_REGION}${NC}"
echo -e "${BLUE}Event bus: ${EVENT_BUS_NAME}${NC}"

# Install Node.js if not present
if ! command -v node &> /dev/null; then
    echo -e "${YELLOW}📦 Installing Node.js...${NC}"
    curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
    sudo apt-get install -y nodejs
fi

echo -e "${GREEN}✅ Node.js version: $(node --version)${NC}"

# Install zip if not present
if ! command -v zip &> /dev/null; then
    echo -e "${YELLOW}📦 Installing zip utility...${NC}"
    sudo apt-get update
    sudo apt-get install -y zip
fi

echo -e "${GREEN}✅ Zip utility available${NC}"

# Create deployment packages
echo -e "${YELLOW}📦 Creating Lambda deployment packages...${NC}"

# Event Logger Lambda
cd lambdas/event-logger
npm install --production
zip -r event-logger.zip index.js node_modules/ package.json
echo -e "${GREEN}✅ Event logger package created${NC}"

# Dead Letter Processor Lambda  
cd ../dead-letter-processor
npm install --production
zip -r dead-letter-processor.zip index.js node_modules/ package.json
echo -e "${GREEN}✅ Dead letter processor package created${NC}"

cd ../..

# Get IAM role ARNs from Terraform
cd terraform
EVENT_PROCESSOR_ROLE_ARN=$(terraform output -raw event_processor_role_arn 2>/dev/null || echo "")
if [ -z "$EVENT_PROCESSOR_ROLE_ARN" ]; then
    echo -e "${YELLOW}⚠️  Event processor role not found in Terraform state. Creating basic role...${NC}"
    
    # Create basic Lambda execution role
    aws iam create-role --role-name EventProcessorBasicRole --assume-role-policy-document '{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": {
                    "Service": "lambda.amazonaws.com"
                },
                "Action": "sts:AssumeRole"
            }
        ]
    }' || true
    
    aws iam attach-role-policy \
        --role-name EventProcessorBasicRole \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole || true
    
    EVENT_PROCESSOR_ROLE_ARN="arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/EventProcessorBasicRole"
fi

cd ..

echo -e "${BLUE}Using IAM role: ${EVENT_PROCESSOR_ROLE_ARN}${NC}"

# Deploy Event Logger Lambda
echo -e "${YELLOW}🚀 Deploying Event Logger Lambda...${NC}"
EVENT_LOGGER_ARN=$(aws lambda create-function \
    --function-name "dev-event-logger" \
    --runtime "nodejs18.x" \
    --role "${EVENT_PROCESSOR_ROLE_ARN}" \
    --handler "index.handler" \
    --zip-file "fileb://lambdas/event-logger/event-logger.zip" \
    --description "Logs all EventBridge events for monitoring" \
    --timeout 30 \
    --memory-size 128 \
    --region "${AWS_REGION}" \
    --query 'FunctionArn' \
    --output text 2>/dev/null || \
aws lambda update-function-code \
    --function-name "dev-event-logger" \
    --zip-file "fileb://lambdas/event-logger/event-logger.zip" \
    --region "${AWS_REGION}" \
    --query 'FunctionArn' \
    --output text)

echo -e "${GREEN}✅ Event Logger deployed: ${EVENT_LOGGER_ARN}${NC}"

# Deploy Dead Letter Processor Lambda
echo -e "${YELLOW}🚀 Deploying Dead Letter Processor Lambda...${NC}"
DLQ_PROCESSOR_ARN=$(aws lambda create-function \
    --function-name "dev-dead-letter-processor" \
    --runtime "nodejs18.x" \
    --role "${EVENT_PROCESSOR_ROLE_ARN}" \
    --handler "index.handler" \
    --zip-file "fileb://lambdas/dead-letter-processor/dead-letter-processor.zip" \
    --description "Processes failed events from DLQ" \
    --timeout 60 \
    --memory-size 256 \
    --region "${AWS_REGION}" \
    --query 'FunctionArn' \
    --output text 2>/dev/null || \
aws lambda update-function-code \
    --function-name "dev-dead-letter-processor" \
    --zip-file "fileb://lambdas/dead-letter-processor/dead-letter-processor.zip" \
    --region "${AWS_REGION}" \
    --query 'FunctionArn' \
    --output text)

echo -e "${GREEN}✅ Dead Letter Processor deployed: ${DLQ_PROCESSOR_ARN}${NC}"

# Wait for functions to be ready
echo -e "${YELLOW}⏳ Waiting for Lambda functions to be ready...${NC}"
sleep 10

# Connect Lambda functions to EventBridge rules
if [ ! -z "$EVENT_BUS_NAME" ] && [ "$EVENT_BUS_NAME" != "default" ]; then
    echo -e "${YELLOW}🔗 Connecting Lambda functions to EventBridge rules...${NC}"
    
    # Function to add Lambda permissions and targets
    connect_lambda_to_rule() {
        local lambda_arn="$1"
        local rule_name="$2"
        local function_name="$3"
        
        echo -e "${BLUE}  Connecting ${function_name} to ${rule_name}...${NC}"
        
        # Add permission for EventBridge to invoke Lambda
        aws lambda add-permission \
            --function-name "${function_name}" \
            --statement-id "AllowEventBridgeInvoke-${rule_name}" \
            --action "lambda:InvokeFunction" \
            --principal "events.amazonaws.com" \
            --source-arn "arn:aws:events:${AWS_REGION}:$(aws sts get-caller-identity --query Account --output text):rule/${EVENT_BUS_NAME}/${rule_name}" \
            --region "${AWS_REGION}" > /dev/null 2>&1
        
        # Connect Lambda as target to the rule
        aws events put-targets \
            --rule "${rule_name}" \
            --event-bus-name "${EVENT_BUS_NAME}" \
            --targets "Id"="1","Arn"="${lambda_arn}" \
            --region "${AWS_REGION}" > /dev/null 2>&1
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}  ✅ ${function_name} connected successfully${NC}"
        else
            echo -e "${YELLOW}  ⚠️  Failed to connect ${function_name}${NC}"
        fi
    }
    
    # Connect event-logger to all-events rule
    RULE_NAME="${ENVIRONMENT}-all-events-to-logger"
    if aws events describe-rule --name "${RULE_NAME}" --event-bus-name "${EVENT_BUS_NAME}" --region "${AWS_REGION}" > /dev/null 2>&1; then
        connect_lambda_to_rule "${EVENT_LOGGER_ARN}" "${RULE_NAME}" "dev-event-logger"
    else
        echo -e "${YELLOW}  ⚠️  Rule ${RULE_NAME} not found${NC}"
    fi
    
    echo -e "${GREEN}✅ Lambda connection process completed${NC}"
else
    echo -e "${YELLOW}⚠️  Using default event bus - no custom rules to connect${NC}"
fi

# Update deployment config
cat >> deployment-config.env << EOF
EVENT_LOGGER_ARN=${EVENT_LOGGER_ARN}
DLQ_PROCESSOR_ARN=${DLQ_PROCESSOR_ARN}
EVENT_PROCESSOR_ROLE_ARN=${EVENT_PROCESSOR_ROLE_ARN}
EOF

echo -e "${GREEN}🎉 Step 3 completed successfully!${NC}"
echo -e "${BLUE}Next: Run step-004-test-events.sh${NC}"