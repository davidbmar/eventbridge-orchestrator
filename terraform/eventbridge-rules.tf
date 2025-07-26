# EventBridge Rules Configuration
# This file defines the routing rules for events between services

# Create custom event bus (optional - can use default)
resource "aws_cloudwatch_event_bus" "main" {
  name = "${var.environment}-application-events"
  
  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# Rule: Audio Uploaded → Transcription Service
resource "aws_cloudwatch_event_rule" "audio_uploaded_to_transcription" {
  name           = "${var.environment}-audio-uploaded-to-transcription"
  description    = "Routes audio upload events to transcription service"
  event_bus_name = aws_cloudwatch_event_bus.main.name

  event_pattern = jsonencode({
    source      = ["custom.upload-service"]
    detail-type = ["Audio Uploaded"]
  })

  tags = {
    Environment = var.environment
    Service     = "transcription"
  }
}

# Rule: Transcription Completed → Search Index Service
resource "aws_cloudwatch_event_rule" "transcription_completed_to_search" {
  name           = "${var.environment}-transcription-completed-to-search"
  description    = "Routes completed transcriptions to search indexing"
  event_bus_name = aws_cloudwatch_event_bus.main.name

  event_pattern = jsonencode({
    source      = ["custom.transcription-service"]
    detail-type = ["Transcription Completed"]
    detail = {
      status = ["completed"]
    }
  })

  tags = {
    Environment = var.environment
    Service     = "search"
  }
}

# Rule: Transcription Completed → Notification Service
resource "aws_cloudwatch_event_rule" "transcription_completed_to_notifications" {
  name           = "${var.environment}-transcription-completed-to-notifications"
  description    = "Sends notifications when transcription completes"
  event_bus_name = aws_cloudwatch_event_bus.main.name

  event_pattern = jsonencode({
    source      = ["custom.transcription-service"]
    detail-type = ["Transcription Completed"]
  })

  tags = {
    Environment = var.environment
    Service     = "notifications"
  }
}

# Rule: Document Uploaded → OCR Service
resource "aws_cloudwatch_event_rule" "document_uploaded_to_ocr" {
  name           = "${var.environment}-document-uploaded-to-ocr"
  description    = "Routes document uploads to OCR processing"
  event_bus_name = aws_cloudwatch_event_bus.main.name

  event_pattern = jsonencode({
    source      = ["custom.upload-service"]
    detail-type = ["Document Uploaded"]
    detail = {
      metadata = {
        format = ["pdf"]
      }
    }
  })

  tags = {
    Environment = var.environment
    Service     = "ocr"
  }
}

# Rule: Video Uploaded → Thumbnail Service
resource "aws_cloudwatch_event_rule" "video_uploaded_to_thumbnail" {
  name           = "${var.environment}-video-uploaded-to-thumbnail"
  description    = "Generates thumbnails for uploaded videos"
  event_bus_name = aws_cloudwatch_event_bus.main.name

  event_pattern = jsonencode({
    source      = ["custom.upload-service"]
    detail-type = ["Video Uploaded"]
  })

  tags = {
    Environment = var.environment
    Service     = "thumbnail"
  }
}

# Rule: User Registered → Welcome Email
resource "aws_cloudwatch_event_rule" "user_registered_to_welcome" {
  name           = "${var.environment}-user-registered-to-welcome"
  description    = "Sends welcome email to new users"
  event_bus_name = aws_cloudwatch_event_bus.main.name

  event_pattern = jsonencode({
    source      = ["custom.auth-service"]
    detail-type = ["User Registered"]
  })

  tags = {
    Environment = var.environment
    Service     = "notifications"
  }
}

# Rule: All Events → Event Logger (for debugging)
resource "aws_cloudwatch_event_rule" "all_events_to_logger" {
  name           = "${var.environment}-all-events-to-logger"
  description    = "Logs all events for debugging and monitoring"
  event_bus_name = aws_cloudwatch_event_bus.main.name

  event_pattern = jsonencode({
    source = [{
      prefix = "custom."
    }]
  })

  tags = {
    Environment = var.environment
    Service     = "monitoring"
  }
}

# Dead Letter Queue for failed event deliveries
resource "aws_sqs_queue" "event_dlq" {
  name                      = "${var.environment}-eventbridge-dlq"
  delay_seconds             = 0
  max_message_size          = 262144
  message_retention_seconds = 1209600  # 14 days
  receive_wait_time_seconds = 0

  tags = {
    Environment = var.environment
    Purpose     = "event-dead-letter-queue"
  }
}

# Archive for event replay capability
resource "aws_cloudwatch_event_archive" "main" {
  name             = "${var.environment}-event-archive"
  event_source_arn = aws_cloudwatch_event_bus.main.arn
  retention_days   = 7

  event_pattern = jsonencode({
    source = [{
      prefix = "custom."
    }]
  })

  description = "Archive for event replay and debugging"
}