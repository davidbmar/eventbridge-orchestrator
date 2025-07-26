# EventBridge Targets Configuration
# This file defines the targets (Lambda functions) for EventBridge rules

# Target: All Events → Event Logger Lambda
resource "aws_cloudwatch_event_target" "all_events_to_logger" {
  count           = var.event_logger_lambda_arn != "" ? 1 : 0
  rule            = aws_cloudwatch_event_rule.all_events_to_logger.name
  event_bus_name  = aws_cloudwatch_event_bus.main.name
  target_id       = "EventLoggerTarget"
  arn             = var.event_logger_lambda_arn

  depends_on = [aws_lambda_permission.eventbridge_invoke]
}

# Target: Audio Uploaded → Transcription Handler Lambda  
resource "aws_cloudwatch_event_target" "audio_to_transcription" {
  count           = var.transcription_handler_lambda_arn != "" ? 1 : 0
  rule            = aws_cloudwatch_event_rule.audio_uploaded_to_transcription.name
  event_bus_name  = aws_cloudwatch_event_bus.main.name
  target_id       = "TranscriptionHandlerTarget"
  arn             = var.transcription_handler_lambda_arn

  depends_on = [aws_lambda_permission.eventbridge_invoke]
}

# Target: Transcription Completed → Search Indexer Lambda
resource "aws_cloudwatch_event_target" "transcription_to_search" {
  count           = var.search_indexer_lambda_arn != "" ? 1 : 0
  rule            = aws_cloudwatch_event_rule.transcription_completed_to_search.name
  event_bus_name  = aws_cloudwatch_event_bus.main.name
  target_id       = "SearchIndexerTarget"
  arn             = var.search_indexer_lambda_arn

  depends_on = [aws_lambda_permission.eventbridge_invoke]
}

# Target: Transcription Completed → Notification Handler Lambda
resource "aws_cloudwatch_event_target" "transcription_to_notifications" {
  count           = var.notification_handler_lambda_arn != "" ? 1 : 0
  rule            = aws_cloudwatch_event_rule.transcription_completed_to_notifications.name
  event_bus_name  = aws_cloudwatch_event_bus.main.name
  target_id       = "NotificationHandlerTarget"
  arn             = var.notification_handler_lambda_arn

  depends_on = [aws_lambda_permission.eventbridge_invoke]
}

# Target: User Registered → Welcome Email Lambda
resource "aws_cloudwatch_event_target" "user_registered_to_welcome" {
  count           = var.notification_handler_lambda_arn != "" ? 1 : 0
  rule            = aws_cloudwatch_event_rule.user_registered_to_welcome.name
  event_bus_name  = aws_cloudwatch_event_bus.main.name
  target_id       = "WelcomeEmailTarget"
  arn             = var.notification_handler_lambda_arn

  depends_on = [aws_lambda_permission.eventbridge_invoke]
}

# Example: Dead Letter Queue Target for failed events
resource "aws_cloudwatch_event_target" "failed_events_to_dlq" {
  rule           = aws_cloudwatch_event_rule.all_events_to_logger.name
  event_bus_name = aws_cloudwatch_event_bus.main.name
  target_id      = "FailedEventsDLQ"
  arn            = aws_sqs_queue.event_dlq.arn

  dead_letter_config {
    arn = aws_sqs_queue.event_dlq.arn
  }

  retry_policy {
    maximum_retry_attempts       = 3
    maximum_event_age_in_seconds = 3600
  }
}