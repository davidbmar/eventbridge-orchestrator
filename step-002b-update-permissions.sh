#!/bin/bash
set -e

echo "🔄 Step 2b: Update IAM Permissions for Existing Lambda Functions"

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
else
    echo -e "${YELLOW}⚠️  No .env file found. Using defaults...${NC}"
    AWS_REGION="us-east-2"
    ENVIRONMENT="dev"
fi

echo -e "${BLUE}Updating permissions in region: ${AWS_REGION}${NC}"

# Function to update Lambda IAM role with CloudWatch permissions
update_lambda_permissions() {
    local role_name="$1"
    
    echo -e "${YELLOW}📋 Updating IAM role: ${role_name}${NC}"
    
    # Check if role exists
    if aws iam get-role --role-name "${role_name}" --region "${AWS_REGION}" > /dev/null 2>&1; then
        echo -e "${BLUE}  Found role: ${role_name}${NC}"
        
        # Create policy document for CloudWatch permissions
        cat > temp-cloudwatch-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "cloudwatch:PutMetricData"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream", 
                "logs:PutLogEvents"
            ],
            "Resource": "*"
        }
    ]
}
EOF
        
        # Apply the policy
        aws iam put-role-policy \
            --role-name "${role_name}" \
            --policy-name "CloudWatchPermissions" \
            --policy-document file://temp-cloudwatch-policy.json
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}  ✅ CloudWatch permissions added to ${role_name}${NC}"
        else
            echo -e "${RED}  ❌ Failed to add permissions to ${role_name}${NC}"
        fi
        
        # Clean up temp file
        rm -f temp-cloudwatch-policy.json
    else
        echo -e "${YELLOW}  ⚠️  Role ${role_name} not found${NC}"
    fi
}

# Update permissions for event processor role
ROLE_NAME="${ENVIRONMENT}-event-processor-role"
update_lambda_permissions "${ROLE_NAME}"

# Update permissions for basic role if it exists
update_lambda_permissions "EventProcessorBasicRole"

echo -e "\n${GREEN}🎉 Permission update completed!${NC}"
echo -e "${BLUE}Lambda functions now have CloudWatch permissions${NC}"
echo -e "${YELLOW}💡 Re-run step-004 to test the updated system${NC}"