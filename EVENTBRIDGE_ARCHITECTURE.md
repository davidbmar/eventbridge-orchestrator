# EventBridge Microservices Architecture

## Overview
This document outlines the architecture for integrating multiple repositories using AWS EventBridge as a central event bus, enabling loose coupling and independent scaling.

## Architecture Design

```
┌─────────────────────────────────────────────────────────────────┐
│                     EventBridge (Central Hub)                   │
└─────────────────┬────────────┬────────────┬────────────┬────────┘
                  │            │            │            │
        ┌─────────▼───┐  ┌────▼────┐  ┌───▼────┐  ┌───▼────┐
        │  Frontend   │  │  Audio  │  │ Search │  │  Auth  │
        │  S3/CDN     │  │  Trans. │  │ Index  │  │  API   │
        └─────────────┘  └─────────┘  └────────┘  └────────┘
         Repo: cognito-   Repo: trans-  Repo:      Repo: auth-
         lambda-s3        cription-sqs  search-    service
```

## Repository Structure

### 1. Current Repositories
- **cognito-lambda-s3-webserver**: Frontend delivery, static assets, user uploads
- **transcription-sqs-spot-s3**: Audio transcription with GPU processing

### 2. New Repository: eventbridge-orchestrator
```
eventbridge-orchestrator/
├── README.md
├── terraform/
│   ├── eventbridge-rules.tf
│   ├── event-schemas.tf
│   └── cross-service-permissions.tf
├── schemas/
│   ├── audio-uploaded.json
│   ├── transcription-completed.json
│   └── user-registered.json
├── lambdas/
│   ├── route-audio-upload/
│   ├── handle-transcription-complete/
│   └── dead-letter-processor/
└── tests/
    └── integration/
```

## Event Flow

### Audio Upload → Transcription Flow
```
1. User uploads audio → S3 PUT → Frontend Lambda
2. Frontend Lambda → Publishes "Audio Uploaded" event → EventBridge
3. EventBridge → Routes to Transcription Lambda
4. Transcription Lambda → Creates job → SQS → GPU Workers
5. GPU Worker completes → Publishes "Transcription Completed" event
6. EventBridge → Routes to Index Service, Notification Service, etc.
```

## Event Schema Example

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "AudioUploaded",
  "type": "object",
  "properties": {
    "version": {"const": "1.0"},
    "source": {"const": "custom.audio-service"},
    "detail-type": {"const": "Audio Uploaded"},
    "detail": {
      "type": "object",
      "properties": {
        "userId": {"type": "string"},
        "fileId": {"type": "string"},
        "s3Location": {
          "type": "object",
          "properties": {
            "bucket": {"type": "string"},
            "key": {"type": "string"}
          }
        },
        "metadata": {
          "type": "object",
          "properties": {
            "duration": {"type": "number"},
            "format": {"type": "string"},
            "size": {"type": "number"}
          }
        }
      },
      "required": ["userId", "fileId", "s3Location"]
    }
  }
}
```

## Integration Examples

### Frontend Publishing Events
```javascript
// cognito-lambda-s3-webserver/src/upload-handler.js
const { EventBridgeClient, PutEventsCommand } = require("@aws-sdk/client-eventbridge");

async function handleFileUpload(s3Event, userContext) {
  // Publish event for other services
  const eventbridge = new EventBridgeClient();
  await eventbridge.send(new PutEventsCommand({
    Entries: [{
      Source: "custom.frontend",
      DetailType: "Audio Uploaded",
      Detail: JSON.stringify({
        version: "1.0",
        userId: userContext.userId,
        fileId: generateFileId(),
        s3Location: {
          bucket: s3Event.bucket,
          key: s3Event.key
        }
      })
    }]
  }));
}
```

### Transcription Service Consuming Events
```python
# transcription-sqs-spot-s3/src/eventbridge_handler.py
def handle_audio_uploaded(event, context):
    """Called by EventBridge when audio is uploaded"""
    detail = event['detail']
    
    job = {
        "job_id": str(uuid.uuid4()),
        "user_id": detail['userId'],
        "file_id": detail['fileId'],
        "s3_input_path": f"s3://{detail['s3Location']['bucket']}/{detail['s3Location']['key']}"
    }
    
    sqs.send_message(
        QueueUrl=TRANSCRIPTION_QUEUE_URL,
        MessageBody=json.dumps(job)
    )
```

## Benefits

1. **Loose Coupling**: Services don't directly depend on each other
2. **Independent Scaling**: Each service scales based on its own needs
3. **Easy Service Addition**: New services just subscribe to events
4. **Technology Flexibility**: Each service can use different tech stacks
5. **Event Replay**: Debug issues by replaying past events
6. **Team Autonomy**: Teams own their repositories independently

## Migration Strategy

### Phase 1: Add EventBridge (No Breaking Changes)
- Create eventbridge-orchestrator repository
- Add event publishing to existing services
- Existing direct integrations continue working

### Phase 2: Gradual Decoupling
- Move from direct API calls to event-driven patterns
- Add new services as event consumers
- Remove direct dependencies over time

## Best Practices

1. **Event Versioning**: Always include version in events
2. **Idempotency**: Design handlers to handle duplicate events
3. **Schema Registry**: Document all event schemas
4. **Error Handling**: Use DLQ for failed events
5. **Monitoring**: Track event flow with CloudWatch metrics

## Next Steps

1. Create `eventbridge-orchestrator` repository
2. Define initial event schemas
3. Add EventBridge publishing to frontend repo
4. Update transcription repo to consume events
5. Deploy EventBridge rules and Lambda handlers

## Documentation Standard

Each repository should document:
- **Events Published**: What events it emits
- **Events Consumed**: What events it listens to
- **Event Schemas**: Links to schema definitions
- **Error Handling**: How failures are managed
