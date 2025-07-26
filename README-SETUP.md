# EventBridge Orchestrator Setup Guide

This guide provides step-by-step instructions to set up the EventBridge orchestrator from scratch.

## Prerequisites

- AWS CLI configured with appropriate credentials
- Ubuntu/Linux environment (or WSL on Windows)
- Internet connection for downloading dependencies

## 🚀 Quick Start

Run these numbered scripts in order for a complete deployment:

### Step 0: Interactive Setup & Configuration
```bash
./step-000-interactive-setup.sh
```
**What it does:**
- Interactive configuration wizard
- Creates `.env` file with your preferences
- Configures AWS region, environment, S3 buckets
- Sets up EventBridge and Lambda options
- Generates Terraform variables automatically

### Step 1: Setup IAM Permissions
```bash
./step-010-setup-iam-permissions.sh
```
**What it does:**
- Creates comprehensive IAM policy for EventBridge, Lambda, SQS, and Schemas
- Applies policy to your current IAM user
- Tests that EventBridge permissions are working

### Step 2: Deploy Infrastructure  
```bash
./step-020-deploy-infrastructure.sh
```
**What it does:**
- Installs Terraform if not present
- Deploys EventBridge custom bus, rules, schemas, and IAM roles
- Creates SQS dead letter queue and monitoring
- Creates deployment-config.env for subsequent steps

### Step 4: Deploy Lambda Functions
```bash
./step-040-deploy-lambdas.sh
```
**What it does:**
- Installs Node.js and dependencies if not present
- Packages and deploys event-logger Lambda function
- Packages and deploys dead-letter-processor Lambda function
- Connects Lambda functions to EventBridge rules with proper permissions
- **Robust fallback**: Works with any config source or defaults

### Step 5: Test the System
```bash
./step-050-test-events.sh
```
**What it does:**
- Tests all event types (Audio, Document, Video, Transcription)
- Publishes sample events to EventBridge
- Tests batch event publishing
- Verifies Lambda functions receive and process events
- Checks CloudWatch logs for end-to-end verification
- Creates detailed test results summary

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

**Step-000 Configuration Issues:**
- Ensure AWS CLI is configured: `aws configure list`
- Check AWS credentials have basic permissions
- If `.env` exists, you can update specific values manually

**IAM Permission Errors (Step-010):**
- Make sure step-010 completed successfully  
- Check that your AWS CLI is configured with the correct user
- Some AWS organizations have additional restrictions
- Verify with: `aws sts get-caller-identity`

**Terraform Deployment Fails (Step-020):**
- Check that step-010 IAM permissions completed
- Verify your AWS region is set correctly in `.env`
- Some resources may require additional permissions in enterprise environments
- Run `terraform plan` in the terraform/ directory to diagnose

**Lambda Deployment Fails (Step-040):**
- **New robust design**: Step-040 now works even without deployment-config.env
- Ensure Node.js is installed (auto-installed if missing)
- Check that EventBridge infrastructure exists (from step-020)
- Scripts now fall back gracefully to defaults if config is missing

**Events Not Publishing (Step-050):**
- Verify EventBridge permissions and bus exists
- Check that your AWS region matches deployment region
- **New feature**: Step-050 validates Lambda log integration
- Use test results in `test-results.json` for debugging

### Getting Help

1. **Check AWS CloudTrail** for detailed error messages
2. **View CloudWatch Logs** for Lambda function errors
3. **Run with verbose output:** Add `set -x` to the top of any script
4. **Test minimal functionality:** Try publishing to the default event bus first

## File Structure

After setup, your directory will contain:

```
eventbridge-orchestrator/
├── step-000-interactive-setup.sh       # Interactive configuration
├── step-010-setup-iam-permissions.sh   # IAM setup
├── step-020-deploy-infrastructure.sh   # Terraform deployment  
├── step-040-deploy-lambdas.sh         # Lambda deployment
├── step-050-test-events.sh            # Testing script
├── step-999-destroy-everything.sh     # Complete cleanup
├── .env                               # User configuration
├── deployment-config.env              # Generated deployment config
├── test-results.json                  # Test results
├── schemas/                           # Event schemas
├── terraform/                         # Infrastructure code
├── lambdas/                          # Lambda functions
└── examples/                         # Test event files
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