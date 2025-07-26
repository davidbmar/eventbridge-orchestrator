/**
 * Integration Tests for EventBridge Event Flow
 * Tests the complete event publishing and consumption flow
 */

const AWS = require('aws-sdk');
const { v4: uuidv4 } = require('uuid');

// Configure AWS SDK for testing
const eventbridge = new AWS.EventBridge({
    region: process.env.AWS_REGION || 'us-east-1'
});

const EVENT_BUS_NAME = process.env.TEST_EVENT_BUS_NAME || 'test-application-events';

describe('EventBridge Integration Tests', () => {
    
    test('should publish and validate Audio Uploaded event', async () => {
        const testEvent = {
            Source: 'custom.upload-service',
            DetailType: 'Audio Uploaded',
            Detail: JSON.stringify({
                userId: 'test-user-123',
                fileId: uuidv4(),
                s3Location: {
                    bucket: 'test-audio-bucket',
                    key: 'test-user-123/test-file.mp3'
                },
                metadata: {
                    format: 'mp3',
                    size: 1024000,
                    contentType: 'audio/mpeg'
                }
            }),
            EventBusName: EVENT_BUS_NAME
        };
        
        const result = await eventbridge.putEvents({
            Entries: [testEvent]
        }).promise();
        
        expect(result.FailedEntryCount).toBe(0);
        expect(result.Entries[0].EventId).toBeDefined();
        
        console.log('Audio Uploaded event published successfully:', result.Entries[0].EventId);
    });
    
    test('should publish and validate Document Uploaded event', async () => {
        const testEvent = {
            Source: 'custom.upload-service',
            DetailType: 'Document Uploaded',
            Detail: JSON.stringify({
                userId: 'test-user-456',
                fileId: uuidv4(),
                s3Location: {
                    bucket: 'test-document-bucket',
                    key: 'test-user-456/test-document.pdf'
                },
                metadata: {
                    format: 'pdf',
                    size: 2048000,
                    contentType: 'application/pdf'
                }
            }),
            EventBusName: EVENT_BUS_NAME
        };
        
        const result = await eventbridge.putEvents({
            Entries: [testEvent]
        }).promise();
        
        expect(result.FailedEntryCount).toBe(0);
        expect(result.Entries[0].EventId).toBeDefined();
        
        console.log('Document Uploaded event published successfully:', result.Entries[0].EventId);
    });
    
    test('should publish and validate Transcription Completed event', async () => {
        const testEvent = {
            Source: 'custom.transcription-service',
            DetailType: 'Transcription Completed',
            Detail: JSON.stringify({
                userId: 'test-user-789',
                fileId: uuidv4(),
                jobId: uuidv4(),
                status: 'completed',
                sourceAudio: {
                    bucket: 'test-audio-bucket',
                    key: 'test-user-789/audio-file.mp3'
                },
                transcriptLocation: {
                    bucket: 'test-transcript-bucket',
                    textKey: 'test-user-789/transcript.txt',
                    jsonKey: 'test-user-789/transcript.json'
                },
                transcriptMetadata: {
                    language: 'en',
                    duration: 180,
                    wordCount: 450,
                    model: 'whisper-large-v3'
                },
                completedAt: new Date().toISOString()
            }),
            EventBusName: EVENT_BUS_NAME
        };
        
        const result = await eventbridge.putEvents({
            Entries: [testEvent]
        }).promise();
        
        expect(result.FailedEntryCount).toBe(0);
        expect(result.Entries[0].EventId).toBeDefined();
        
        console.log('Transcription Completed event published successfully:', result.Entries[0].EventId);
    });
    
    test('should publish batch of events successfully', async () => {
        const events = [
            {
                Source: 'custom.upload-service',
                DetailType: 'Audio Uploaded',
                Detail: JSON.stringify({
                    userId: 'batch-test-1',
                    fileId: uuidv4(),
                    s3Location: {
                        bucket: 'test-bucket',
                        key: 'batch-test-1/file1.mp3'
                    },
                    metadata: {
                        format: 'mp3',
                        size: 1024,
                        contentType: 'audio/mpeg'
                    }
                })
            },
            {
                Source: 'custom.upload-service',
                DetailType: 'Document Uploaded',
                Detail: JSON.stringify({
                    userId: 'batch-test-2',
                    fileId: uuidv4(),
                    s3Location: {
                        bucket: 'test-bucket',
                        key: 'batch-test-2/file2.pdf'
                    },
                    metadata: {
                        format: 'pdf',
                        size: 2048,
                        contentType: 'application/pdf'
                    }
                })
            }
        ];
        
        const result = await eventbridge.putEvents({
            Entries: events.map(event => ({
                ...event,
                EventBusName: EVENT_BUS_NAME
            }))
        }).promise();
        
        expect(result.FailedEntryCount).toBe(0);
        expect(result.Entries).toHaveLength(2);
        
        console.log('Batch events published successfully:', result.Entries.map(e => e.EventId));
    });
    
    test('should handle invalid event gracefully', async () => {
        const invalidEvent = {
            Source: 'custom.upload-service',
            DetailType: 'Invalid Event',
            Detail: JSON.stringify({
                // Missing required fields
                invalidField: 'test'
            }),
            EventBusName: EVENT_BUS_NAME
        };
        
        const result = await eventbridge.putEvents({
            Entries: [invalidEvent]
        }).promise();
        
        // EventBridge should accept the event even if it doesn't match schema
        // Schema validation happens at the consumer level
        expect(result.FailedEntryCount).toBe(0);
        
        console.log('Invalid event handled:', result.Entries[0].EventId);
    });
});

// Helper function to wait for eventual consistency
async function waitForEventProcessing(eventId, timeoutMs = 5000) {
    return new Promise(resolve => {
        setTimeout(() => {
            console.log(`Waited for event processing: ${eventId}`);
            resolve();
        }, timeoutMs);
    });
}