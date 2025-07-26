# EventBridge Orchestrator Setup Guide

This guide provides step-by-step instructions to set up the EventBridge orchestrator from scratch.

## Prerequisites

- AWS CLI configured with appropriate credentials
- Ubuntu/Linux environment (or WSL on Windows)
- Internet connection for downloading dependencies

## Quick Start

Run these numbered scripts in order:

### Step 1: Setup IAM Permissions
```bash
./step-001-setup-iam-permissions.sh
```
**What it does:**
- Creates comprehensive IAM policy for EventBridge, Lambda, SQS, and Schemas
- Applies policy to your current IAM user
- Tests that EventBridge permissions are working

### Step 2: Deploy Infrastructure  
```bash
./step-002-deploy-infrastructure.sh
```
**What it does:**
- Installs Terraform if not present
- Configures Terraform for your AWS region
- Deploys EventBridge custom bus, rules, schemas, and IAM roles
- Creates SQS dead letter queue
- Saves deployment configuration for next steps

### Step 3: Deploy Lambda Functions
```bash
./step-003-deploy-lambdas.sh
```
**What it does:**
- Installs Node.js if not present
- Packages and deploys event-logger Lambda function
- Packages and deploys dead-letter-processor Lambda function
- Configures Lambda permissions

### Step 4: Test the System
```bash
./step-004-test-events.sh
```
**What it does:**
- Tests all event types (Audio, Document, Video, Transcription)
- Publishes sample events to EventBridge
- Tests batch event publishing
- Checks Lambda logs
- Creates test results summary

## Manual Setup (Alternative)

If you prefer manual setup or the scripts don't work in your environment:

### 1. Install Dependencies
```bash
# Install Terraform
curl -fsSL https://releases.hashicorp.com/terraform/1.6.6/terraform_1.6.6_linux_amd64.zip -o terraform.zip
unzip terraform.zip && sudo mv terraform /usr/local/bin/

# Install Node.js (for Lambda functions)
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs
```

### 2. Configure IAM Permissions
Create and attach this policy to your IAM user:
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "events:*",
                "schemas:*",
                "sqs:*",
                "iam:CreateRole",
                "iam:PutRolePolicy",
                "iam:AttachRolePolicy",
                "iam:PassRole",
                "lambda:*",
                "cloudwatch:*",
                "logs:*"
            ],
            "Resource": "*"
        }
    ]
}
```

### 3. Deploy with Terraform
```bash
cd terraform
terraform init
terraform plan
terraform apply
```

### 4. Test EventBridge
```bash
aws events put-events --entries file://examples/test-audio-upload-event.json --region us-east-2
```

## Troubleshooting

### Common Issues

**IAM Permission Errors:**
- Make sure step 1 completed successfully
- Check that your AWS CLI is configured with the correct user
- Some AWS organizations have additional restrictions

**Terraform Deployment Fails:**
- Check that you have sufficient IAM permissions
- Verify your AWS region is set correctly
- Some resources may require additional permissions in enterprise environments

**Lambda Deployment Fails:**
- Ensure Node.js is installed (`node --version`)
- Check that the IAM role exists
- Verify the zip files were created in the lambdas directories

**Events Not Publishing:**
- Verify EventBridge permissions with: `aws events describe-event-bus --name default`
- Check that your AWS region matches the deployment region
- Ensure JSON syntax is correct in test files

### Getting Help

1. **Check AWS CloudTrail** for detailed error messages
2. **View CloudWatch Logs** for Lambda function errors
3. **Run with verbose output:** Add `set -x` to the top of any script
4. **Test minimal functionality:** Try publishing to the default event bus first

## File Structure

After setup, your directory will contain:

```
eventbridge-orchestrator/
├── step-001-setup-iam-permissions.sh    # IAM setup
├── step-002-deploy-infrastructure.sh    # Terraform deployment  
├── step-003-deploy-lambdas.sh          # Lambda deployment
├── step-004-test-events.sh             # Testing script
├── deployment-config.env               # Generated config
├── test-results.json                   # Test results
├── schemas/                            # Event schemas
├── terraform/                          # Infrastructure code
├── lambdas/                           # Lambda functions
└── examples/                          # Test event files
```

## What's Created

The setup creates these AWS resources:

- **EventBridge Custom Bus:** `dev-application-events`
- **EventBridge Rules:** For routing different event types
- **Schema Registry:** With validation schemas for all event types
- **SQS Queue:** Dead letter queue for failed events
- **IAM Roles:** For Lambda execution and EventBridge permissions
- **Lambda Functions:** event-logger and dead-letter-processor
- **CloudWatch:** Log groups for monitoring

## Next Steps

After successful setup:

1. **Integrate with your services:** Use the IAM roles and event schemas to publish events from your applications
2. **Add custom rules:** Create EventBridge rules to route events to your specific Lambda functions
3. **Set up monitoring:** Use CloudWatch dashboards to monitor event flow
4. **Scale the system:** Add more event types and processing services as needed

## Production Considerations

- **Security:** Use least-privilege IAM policies in production
- **Monitoring:** Set up CloudWatch alarms for failed events
- **Cost:** Monitor EventBridge and Lambda costs, especially for high-volume events
- **Backup:** Consider cross-region replication for critical event flows