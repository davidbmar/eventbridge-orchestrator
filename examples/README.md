# Testing Examples

This directory contains example event payloads for testing the EventBridge orchestrator.

## Testing Commands

### 1. Test Audio Upload Event
```bash
aws events put-events --entries file://examples/test-audio-upload-event.json
```

### 2. Test with Custom Event Bus (after deployment)
```bash
aws events put-events --entries file://examples/test-audio-upload-event.json
```

### 3. Validate Schema
```bash
aws schemas describe-schema \
  --registry-name dev-event-schemas \
  --schema-name AudioUploaded
```

## Prerequisites

1. **Deploy infrastructure first:**
   ```bash
   cd terraform
   terraform init
   terraform plan
   terraform apply
   ```

2. **Configure AWS credentials:**
   ```bash
   aws configure
   ```

3. **Ensure you have permissions to:**
   - Put events to EventBridge
   - Invoke Lambda functions
   - Access CloudWatch logs

## Monitoring

After sending test events, check:
- **CloudWatch Logs** for Lambda function execution
- **EventBridge metrics** in CloudWatch
- **Dead letter queue** for any failed events

## Event Flow Testing

1. Send audio upload event → Should trigger transcription handler
2. Send transcription completed event → Should trigger search indexer
3. Check event logger Lambda logs for all events received