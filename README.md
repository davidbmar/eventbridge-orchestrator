
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

## **Common Questions**

### **Q: What happens if my service is offline when events are sent?**

* EventBridge will retry, and if it still fails, the event goes to a **dead-letter queue** so you can reprocess it later.

### **Q: How do I add a new service?**

1. Create a new repo.
2. Subscribe it to an event (via Terraform here).
3. Implement a Lambda or consumer that processes the event.

### **Q: How do I replay old events?**

* EventBridge can archive and replay events. You can also reprocess from logs or dead-letter queues.


