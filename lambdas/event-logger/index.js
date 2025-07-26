/**
 * Event Logger Lambda Function
 * Logs all events for monitoring, debugging, and auditing purposes
 */

const AWS = require('aws-sdk');
const cloudwatch = new AWS.CloudWatch();

exports.handler = async (event) => {
    console.log('Received event:', JSON.stringify(event, null, 2));
    
    try {
        // Extract event details
        const eventSource = event.source || 'unknown';
        const eventType = event['detail-type'] || 'unknown';
        const eventTime = event.time || new Date().toISOString();
        const eventDetail = event.detail || {};
        
        // Log structured data for CloudWatch Insights
        console.log(JSON.stringify({
            logType: 'EVENT_RECEIVED',
            eventId: event.id,
            eventSource,
            eventType,
            eventTime,
            userId: eventDetail.userId || 'unknown',
            fileId: eventDetail.fileId || 'unknown',
            status: eventDetail.status || 'unknown',
            metadata: {
                region: event.region,
                account: event.account,
                resources: event.resources
            }
        }));
        
        // Send custom metrics to CloudWatch
        const metricData = [
            {
                MetricName: 'EventsReceived',
                Value: 1,
                Unit: 'Count',
                Timestamp: new Date(),
                Dimensions: [
                    {
                        Name: 'EventSource',
                        Value: eventSource
                    },
                    {
                        Name: 'EventType',
                        Value: eventType
                    }
                ]
            }
        ];
        
        // Add specific metrics based on event type
        if (eventType === 'Transcription Completed' && eventDetail.status) {
            metricData.push({
                MetricName: 'TranscriptionStatus',
                Value: 1,
                Unit: 'Count',
                Timestamp: new Date(),
                Dimensions: [
                    {
                        Name: 'Status',
                        Value: eventDetail.status
                    }
                ]
            });
            
            // Log processing time if available
            if (eventDetail.transcriptMetadata?.processingTime) {
                metricData.push({
                    MetricName: 'TranscriptionProcessingTime',
                    Value: eventDetail.transcriptMetadata.processingTime,
                    Unit: 'Seconds',
                    Timestamp: new Date()
                });
            }
        }
        
        // Send metrics to CloudWatch
        await cloudwatch.putMetricData({
            Namespace: 'EventBridge/Events',
            MetricData: metricData
        }).promise();
        
        // Check for anomalies or issues
        if (eventDetail.error) {
            console.error('Event contains error:', JSON.stringify({
                logType: 'EVENT_ERROR',
                eventId: event.id,
                eventType,
                error: eventDetail.error
            }));
        }
        
        return {
            statusCode: 200,
            body: JSON.stringify({
                message: 'Event logged successfully',
                eventId: event.id
            })
        };
        
    } catch (error) {
        console.error('Error processing event:', error);
        
        // Still return success to prevent retry storms
        return {
            statusCode: 200,
            body: JSON.stringify({
                message: 'Event logged with errors',
                eventId: event.id,
                error: error.message
            })
        };
    }
};