#!/bin/bash
set -e

echo "🚀 Deploying EventBridge Orchestrator to us-east-2"

# Check AWS credentials
echo "📋 Checking AWS configuration..."
aws sts get-caller-identity

# Install Terraform if not present
if ! command -v terraform &> /dev/null; then
    echo "📦 Installing Terraform..."
    curl -fsSL https://releases.hashicorp.com/terraform/1.6.6/terraform_1.6.6_linux_amd64.zip -o terraform.zip
    unzip -o terraform.zip
    sudo mv terraform /usr/local/bin/
    rm terraform.zip
fi

echo "✅ Terraform version: $(terraform --version | head -n1)"

# Deploy infrastructure
echo "🏗️  Deploying infrastructure..."
cd terraform

echo "📝 Initializing Terraform..."
terraform init

echo "📋 Planning deployment..."
terraform plan

echo "🚀 Applying changes..."
terraform apply -auto-approve

echo "✅ Deployment complete!"
echo "🔍 You can now test with:"
echo "   aws events put-events --entries file://examples/test-audio-upload-event.json --region us-east-2"