
# **EventBridge Orchestrator**

This repository is the **central nervous system** of our system. It defines **how services talk to each other** using AWS EventBridge, ensures events are consistent using **schemas**, and makes it easy to add or update services.

---

## **What is EventBridge?**

Think of EventBridge as a **post office**:

* Services (like the frontend or transcription) **send events** (letters).
* EventBridge **routes events** to any service that wants to listen (subscribers).
* Services don’t need to know about each other directly.
  → This keeps everything **modular, testable, and independent**.

---

## **How the System Works**

### **High-Level Flow (Horizontal)**

```
                     EventBridge (Central Hub)
 ┌─────────────────────────────────────────────────────────────┐
 │                                                             │
 └───────────┬─ ───────────┬────────────┬──────────────────────┘
             │             │            │
             │             │            │
        Frontend       Transcription   Search           Notification
        (S3/CDN)       (GPU + SQS)     (Elasticsearch)   (Optional)

   Repo: audio-ui-    Repo:transcription-   Repo:search-      Repo:notification-
   cf-s3-lambda-      sqs-spot-s3           index-service     service
   cognito

   👉 [Link](https://github.com/davidbmar/audio-ui-cf-s3-lambda-cognito)
   👉 [Link](https://github.com/davidbmar/transcription-sqs-spot-s3/tree/main/scripts)
```

### **How to Read This**

1. **EventBridge is the central hub**:
   All services connect to EventBridge. They either **publish** events or **consume** events.

   * Example: Frontend publishes `AudioUploaded`.
   * Transcription consumes `AudioUploaded`, processes the audio, and then publishes `TranscriptionCompleted`.

2. **Repos are independent**:
   Each box in the diagram maps to a **GitHub repository**:

   * **Frontend (S3/CDN):**
     [`audio-ui-cf-s3-lambda-cognito`](https://github.com/davidbmar/audio-ui-cf-s3-lambda-cognito)
   * **Transcription (GPU + SQS):**
     [`transcription-sqs-spot-s3`](https://github.com/davidbmar/transcription-sqs-spot-s3/tree/main/scripts)
   * **Search (Elasticsearch):**
     `search-index-service` *(future repo or internal)*
   * **Notification (Optional):**
     `notification-service` *(can be added easily)*

3. **SQS & GPU are details of the Transcription Service:**

   * EventBridge triggers a Lambda in the Transcription repo.
   * That Lambda pushes jobs into an **SQS queue**.
   * **GPU pods** pick up jobs from SQS, process audio, and publish a `TranscriptionCompleted` event.

---

## **Example: Transcription Service Detailed Flow**

> **Note:** This diagram is **not part of the EventBridge Orchestrator repo**. It’s here as an example of how a single service (Transcription) interacts with EventBridge.

```
        EventBridge (AudioUploaded)
                     │
                     ▼
          Transcription Lambda (Listener)
                     │
          Pushes job details into SQS Queue
                     │
                     ▼
          SQS Queue (transcription-jobs)
                     │
        GPU Pods poll SQS and process jobs
                     │
     Saves transcript to S3 and publishes:
                     │
         EventBridge (TranscriptionCompleted)
```

### **Key Points**

* The **Lambda listener** is triggered by EventBridge when it receives an `AudioUploaded` event.
* Jobs are pushed into an **SQS queue** to decouple GPU workloads from EventBridge and allow batching/backpressure.
* **GPU pods** (transcription workers) pull jobs from SQS when available and process them.
* After completing transcription, the service **publishes a new event** (`TranscriptionCompleted`) back to EventBridge for other services (e.g., Search, Notifications).

---

## **Schemas: The Event Contracts**

Schemas are **JSON documents** that describe what an event looks like.

* They ensure all services agree on field names and types.
* They help us avoid breaking other services when we change an event.

### **Example: `audio-uploaded.v1.json`**

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "AudioUploaded",
  "type": "object",
  "properties": {
    "userId": { "type": "string" },
    "fileId": { "type": "string" },
    "s3Location": {
      "type": "object",
      "properties": {
        "bucket": { "type": "string" },
        "key": { "type": "string" }
      },
      "required": ["bucket", "key"]
    },
    "metadata": {
      "type": "object",
      "properties": {
        "format": { "type": "string" },
        "size": { "type": "number" },
        "uploadTime": { "type": "string", "format": "date-time" }
      }
    }
  },
  "required": ["userId", "fileId", "s3Location"]
}
```

---

## **Versioning & Migrations**

* **Never break existing consumers.**
* If you need to change a field name or type:

  1. Add a new schema version (e.g., `audio-uploaded.v2.json`).
  2. Publish both `v1` and `v2` events for a transition period.
  3. Give consumers time to upgrade.
  4. Remove `v1` when no one uses it.

**Rule:** Once a schema is published, **don’t edit it**. Always add a new version.

---

## **Folder Structure**

```
eventbridge-orchestrator/
├── schemas/                # Event schemas (JSON)
│   ├── audio-uploaded.v1.json
│   ├── transcription-completed.v1.json
│   └── user-registered.v1.json
├── lambdas/                # Utility Lambdas
│   ├── event-logger/       # Logs all events for debugging
│   └── dead-letter-processor/
├── terraform/              # EventBridge rules & infra
│   ├── eventbridge-rules.tf
│   ├── event-schemas.tf
│   └── cross-service-permissions.tf
└── README.md
```

---

## **Best Practices**

1. **Validate events on both ends:** Publishers and consumers should both validate payloads.
2. **Be backward compatible:** Add fields instead of removing or renaming them.
3. **Version your schemas:** `v1`, `v2`, etc. Never change an existing version.
4. **Test with example events:** Each schema has an example JSON you can use for tests.
5. **Use dead-letter queues:** If a service fails, events won’t be lost.

---

## **🚀 Quick Start Deployment**

Deploy the complete EventBridge orchestrator with **enterprise-grade robustness and error handling**:

### **🎯 Automated Deployment (Recommended)**

```bash
# Clone and deploy everything automatically
git clone https://github.com/davidbmar/eventbridge-orchestrator.git
cd eventbridge-orchestrator

# One-command deployment with full automation
./deploy-all.sh

# Or for production-ready automated deployment
./deploy-all.sh --auto-approve --fresh-start
```

### **📋 Manual Step-by-Step Deployment**

```bash
# 1. Check prerequisites and system readiness
./step-001-preflight-check.sh       # NEW: Validates prerequisites

# 2. Run deployment steps with enhanced error handling
./step-000-interactive-setup.sh      # Interactive configuration
./step-010-setup-iam-permissions.sh  # AWS IAM permissions (with retry logic)
./step-020-deploy-infrastructure.sh  # EventBridge + Terraform (handles schema errors)
./step-040-deploy-lambdas.sh        # Lambda functions
./step-050-test-events.sh           # End-to-end testing (comprehensive health check)

# 3. Check deployment status anytime
./deployment-status.sh              # NEW: Real-time deployment monitoring
```

### **🔧 Deployment Options**

| Command | Description | Use Case |
|---------|-------------|----------|
| `./deploy-all.sh` | Interactive full deployment | First-time setup |
| `./deploy-all.sh --auto-approve` | Non-interactive deployment | CI/CD pipelines |
| `./deploy-all.sh --fresh-start` | Clean state and redeploy | Troubleshooting |
| `./deploy-all.sh --skip-preflight` | Skip prerequisite checks | Expert users |
| `./deployment-status.sh` | Check deployment progress | Status monitoring |

### **✨ Enhanced Features**

#### **🛡️ Robust Error Handling**
- **Automatic retries** with exponential backoff
- **Schema registry error handling** (known AWS API limitations)
- **State tracking** with checkpoint recovery
- **Graceful degradation** for non-critical failures

#### **📊 Deployment Monitoring**
- **Real-time status tracking** with `.deployment-state/` directory
- **Error and warning logs** with timestamps
- **AWS resource health checks** 
- **Progress visualization** with step-by-step status

#### **🔄 Recovery & Resilience**
- **Resume interrupted deployments** from checkpoints
- **Clean state management** with fresh start option
- **Prerequisites validation** before deployment
- **Comprehensive logging** for troubleshooting

### **What Each Step Does**

| Step | Name | Description | Enhanced Features |
|------|------|-------------|-------------------|
| **001** | **Preflight Check** | Validates system prerequisites | ✅ Tool validation, AWS credentials, disk space |
| **000** | Interactive Setup | Configures environment variables | ✅ Creates `.env` file, Terraform variables |
| **010** | IAM Permissions | Sets up AWS permissions | ✅ Retry logic, permission validation |
| **020** | Infrastructure | Deploys EventBridge infrastructure | ✅ Schema error handling, Terraform retry |
| **040** | Lambda Functions | Deploys event processing functions | ✅ Error recovery, validation checks |
| **050** | Testing | Comprehensive end-to-end validation | ✅ Operational health check, detailed reporting |

### **💾 State Management**

The deployment system now maintains state in `.deployment-state/`:
```
.deployment-state/
├── checkpoints.log          # Step completion tracking
├── errors.log              # Error history with timestamps  
├── warnings.log            # Warning history
├── deployment.log          # Detailed operation log
├── step-*.status           # Individual step status files
└── step-*.log             # Per-step execution logs
```

### **🧹 Clean Deployment Destruction**

```bash
# Two-phase destroy for dependency handling
./step-998-pre-destroy-cleanup.sh    # Handles AWS API dependencies
./step-999-destroy-everything.sh     # Terraform destroy
```

---

## **📋 Components Overview**

### **Core Infrastructure**
- **🔄 EventBridge Custom Bus**: `{environment}-application-events`
- **📋 Schema Registry**: JSON Schema validation for all events
- **⚡ Lambda Functions**: Event logging and dead-letter processing
- **📨 SQS Dead Letter Queue**: Failed event handling
- **🔐 IAM Roles**: Cross-service permissions

### **Event Types Supported**
- 🎵 **Audio Uploaded** - Audio file processing triggers
- 📄 **Document Uploaded** - Document processing events  
- 🎬 **Video Uploaded** - Video processing triggers
- 📝 **Transcription Completed** - Audio processing results
- 👤 **User Registered** - User lifecycle events

### **Integration Points**
- **Frontend Integration**: [`audio-ui-cf-s3-lambda-cognito`](https://github.com/davidbmar/audio-ui-cf-s3-lambda-cognito) with EventBridge publishing
- **Processing Integration**: [`transcription-sqs-spot-s3`](https://github.com/davidbmar/transcription-sqs-spot-s3) event consumption

---

## **🔧 Troubleshooting Guide**

### **🚨 Common Issues & Solutions**

#### **Schema Registry Permission Errors**
```
Error: User is not authorized to perform: schemas:ListTagsForResource
```
**Solution:** This is a known AWS API limitation and is **non-critical**. The deployment continues successfully.
- ✅ **Status:** EventBridge functionality is not affected
- ✅ **Action:** No action needed - deployment proceeds normally

#### **Terraform Destroy Hanging**
```
Error: Rule can't be deleted since it has targets
```
**Solution:** Use the two-phase destroy process:
```bash
./step-998-pre-destroy-cleanup.sh    # Remove dependencies first
./step-999-destroy-everything.sh     # Then run Terraform destroy
```

#### **AWS Credentials Not Found**
```
Error: AWS credentials not configured
```
**Solution:** Configure AWS CLI credentials:
```bash
aws configure
# Or set environment variables:
export AWS_ACCESS_KEY_ID=your_key
export AWS_SECRET_ACCESS_KEY=your_secret
export AWS_DEFAULT_REGION=us-east-2
```

#### **Missing Prerequisites**
```
Error: Required command 'terraform' not found
```
**Solution:** Run preflight check for detailed installation instructions:
```bash
./step-001-preflight-check.sh
```

### **📊 Monitoring & Debugging**

#### **Check Deployment Status**
```bash
./deployment-status.sh              # Overall status
cat .deployment-state/errors.log    # Error details
cat .deployment-state/warnings.log  # Warning details
```

#### **View Step-Specific Logs**
```bash
ls .deployment-state/               # List all logs
cat .deployment-state/step-020-deploy-infrastructure.log
```

#### **Resume Failed Deployment**
```bash
# Check what failed
./deployment-status.sh

# Continue from where it left off
./deploy-all.sh                     # Skips completed steps automatically
```

#### **Fresh Start After Issues**
```bash
./deploy-all.sh --fresh-start       # Clean state and restart
```

### **🔍 Health Checks**

#### **Verify EventBridge Resources**
```bash
# Check EventBridge bus
aws events describe-event-bus --name dev-application-events

# List EventBridge rules  
aws events list-rules --event-bus-name dev-application-events

# Check Lambda functions
aws lambda list-functions --query 'Functions[?contains(FunctionName, `event`)]'
```

#### **Test Event Flow**
```bash
./step-050-test-events.sh           # Comprehensive end-to-end test
```

---

## **Common Questions**

### **Q: What happens if my service is offline when events are sent?**

* EventBridge will retry, and if it still fails, the event goes to a **dead-letter queue** so you can reprocess it later.

### **Q: How do I add a new service?**

1. Create a new repo.
2. Subscribe it to an event (via Terraform here).
3. Implement a Lambda or consumer that processes the event.

### **Q: How do I replay old events?**

* EventBridge can archive and replay events. You can also reprocess from logs or dead-letter queues.

### **Q: How do I integrate my existing services?**

1. Use the IAM roles created by step-020 for EventBridge permissions
2. Reference the schemas in `/schemas/` for event structure
3. See integration examples in the audio upload system repository

### **Q: What's new in the enhanced deployment system?**

**🎯 Production-Ready Features:**
- **Enterprise-grade error handling** with automatic retries
- **State tracking and recovery** - resume from any point
- **Comprehensive logging** with timestamps and categorization
- **AWS API limitation handling** (e.g., schema registry permissions)
- **Prerequisites validation** before deployment begins
- **Real-time monitoring** with deployment status dashboard

**🚀 Deployment Tools:**
- `deploy-all.sh` - Fully automated deployment with options
- `deployment-status.sh` - Real-time progress and health monitoring  
- `step-001-preflight-check.sh` - System readiness validation
- `error-handling.sh` - Common error handling library
- `.deployment-state/` - Persistent state and logging directory

**🔧 Robustness Improvements:**
- **Retry logic** for transient AWS API failures
- **Graceful degradation** for non-critical errors
- **Checkpoint recovery** for interrupted deployments
- **Fresh start capability** for troubleshooting
- **Two-phase destroy** handling AWS dependency constraints

This makes the system suitable for **production environments** and **CI/CD pipelines** while maintaining the simplicity of the original step-by-step approach.

---

## **🎯 For Developers**

### **Adding New Event Types**
1. Create schema in `schemas/` directory
2. Add EventBridge rule in `terraform/eventbridge-rules.tf`
3. Update test cases in `examples/`
4. Deploy with `./step-020-deploy-infrastructure.sh`

### **Integration with CI/CD**
```bash
# Non-interactive deployment for automation
./deploy-all.sh --auto-approve --fresh-start

# Status checking for pipeline validation
./deployment-status.sh && echo "Deployment healthy"
```

### **Local Development**
```bash
# Quick status check during development
./deployment-status.sh

# Test specific event types
aws events put-events --entries file://examples/test-audio-upload.json
```

