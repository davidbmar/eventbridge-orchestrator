/**
 * Dead Letter Processor Lambda Function
 * Processes failed events from the DLQ and attempts recovery or alerts
 */

const AWS = require('aws-sdk');
const sns = new AWS.SNS();
const s3 = new AWS.S3();
const eventbridge = new AWS.EventBridge();

const ALERT_TOPIC_ARN = process.env.ALERT_TOPIC_ARN;
const FAILED_EVENTS_BUCKET = process.env.FAILED_EVENTS_BUCKET || 'eventbridge-failed-events';
const EVENT_BUS_NAME = process.env.EVENT_BUS_NAME || 'default';
const MAX_RETRY_ATTEMPTS = parseInt(process.env.MAX_RETRY_ATTEMPTS || '3');

exports.handler = async (event) => {
    console.log('Processing DLQ event:', JSON.stringify(event, null, 2));
    
    const results = [];
    
    // Process each record from SQS
    for (const record of event.Records) {
        try {
            const message = JSON.parse(record.body);
            const result = await processFailedEvent(message, record);
            results.push(result);
        } catch (error) {
            console.error('Error processing record:', error);
            results.push({
                messageId: record.messageId,
                status: 'error',
                error: error.message
            });
        }
    }
    
    return {
        batchItemFailures: results
            .filter(r => r.status === 'retry')
            .map(r => ({ itemIdentifier: r.messageId }))
    };
};

async function processFailedEvent(message, sqsRecord) {
    const eventDetail = message.detail || {};
    const failureReason = message.failureReason || 'Unknown';
    const retryCount = parseInt(sqsRecord.attributes?.ApproximateReceiveCount || '1');
    
    console.log(`Processing failed event: ${message.id}, retry count: ${retryCount}`);
    
    // Determine action based on retry count and failure reason
    if (retryCount < MAX_RETRY_ATTEMPTS && isRetryable(failureReason)) {
        // Attempt to republish the event
        try {
            await republishEvent(message);
            return {
                messageId: sqsRecord.messageId,
                status: 'republished',
                eventId: message.id
            };
        } catch (error) {
            console.error('Failed to republish event:', error);
        }
    }
    
    // Archive failed event to S3
    const archiveKey = await archiveFailedEvent(message, sqsRecord);
    
    // Send alert for critical events
    if (isCriticalEvent(message)) {
        await sendAlert(message, failureReason, retryCount, archiveKey);
    }
    
    // Log failure metrics
    await logFailureMetrics(message, failureReason);
    
    return {
        messageId: sqsRecord.messageId,
        status: 'processed',
        eventId: message.id,
        archived: archiveKey
    };
}

function isRetryable(failureReason) {
    const retryableReasons = [
        'Lambda throttled',
        'Target unavailable',
        'Timeout',
        'Rate exceeded'
    ];
    
    return retryableReasons.some(reason => 
        failureReason.toLowerCase().includes(reason.toLowerCase())
    );
}

function isCriticalEvent(message) {
    const criticalEventTypes = [
        'Transcription Completed',
        'User Registered',
        'Payment Processed'
    ];
    
    return criticalEventTypes.includes(message['detail-type']);
}

async function republishEvent(message) {
    // Remove any DLQ-specific fields
    const cleanedEvent = {
        Source: message.source,
        DetailType: message['detail-type'],
        Detail: JSON.stringify(message.detail),
        EventBusName: EVENT_BUS_NAME
    };
    
    const result = await eventbridge.putEvents({
        Entries: [cleanedEvent]
    }).promise();
    
    if (result.FailedEntryCount > 0) {
        throw new Error(`Failed to republish event: ${JSON.stringify(result.Entries)}`);
    }
    
    console.log(`Successfully republished event: ${message.id}`);
}

async function archiveFailedEvent(message, sqsRecord) {
    const timestamp = new Date().toISOString();
    const date = timestamp.split('T')[0];
    const key = `failed-events/${date}/${message['detail-type']}/${message.id}-${timestamp}.json`;
    
    const eventData = {
        originalEvent: message,
        sqsMetadata: {
            messageId: sqsRecord.messageId,
            receiptHandle: sqsRecord.receiptHandle,
            attributes: sqsRecord.attributes
        },
        processedAt: timestamp
    };
    
    await s3.putObject({
        Bucket: FAILED_EVENTS_BUCKET,
        Key: key,
        Body: JSON.stringify(eventData, null, 2),
        ContentType: 'application/json',
        Metadata: {
            'event-id': message.id || 'unknown',
            'event-type': message['detail-type'] || 'unknown',
            'user-id': message.detail?.userId || 'unknown'
        }
    }).promise();
    
    console.log(`Archived failed event to S3: ${key}`);
    return key;
}

async function sendAlert(message, failureReason, retryCount, archiveKey) {
    if (!ALERT_TOPIC_ARN) {
        console.warn('No alert topic configured, skipping alert');
        return;
    }
    
    const subject = `Critical Event Failed: ${message['detail-type']}`;
    const alertMessage = `
Critical event processing failed after ${retryCount} attempts.

Event Details:
- Event ID: ${message.id}
- Event Type: ${message['detail-type']}
- Source: ${message.source}
- User ID: ${message.detail?.userId || 'N/A'}
- Failure Reason: ${failureReason}
- Archived Location: s3://${FAILED_EVENTS_BUCKET}/${archiveKey}

Event Detail:
${JSON.stringify(message.detail, null, 2)}

Please investigate immediately.
    `.trim();
    
    await sns.publish({
        TopicArn: ALERT_TOPIC_ARN,
        Subject: subject,
        Message: alertMessage,
        MessageAttributes: {
            eventType: {
                DataType: 'String',
                StringValue: message['detail-type']
            },
            eventId: {
                DataType: 'String',
                StringValue: message.id
            }
        }
    }).promise();
    
    console.log(`Alert sent for critical event: ${message.id}`);
}

async function logFailureMetrics(message, failureReason) {
    const cloudwatch = new AWS.CloudWatch();
    
    await cloudwatch.putMetricData({
        Namespace: 'EventBridge/DeadLetter',
        MetricData: [
            {
                MetricName: 'FailedEvents',
                Value: 1,
                Unit: 'Count',
                Timestamp: new Date(),
                Dimensions: [
                    {
                        Name: 'EventType',
                        Value: message['detail-type'] || 'unknown'
                    },
                    {
                        Name: 'EventSource',
                        Value: message.source || 'unknown'
                    }
                ]
            }
        ]
    }).promise();
}