# Cross-Service IAM Permissions
# Defines IAM roles and policies for services to publish and consume events

# IAM role for services to publish events
resource "aws_iam_role" "event_publisher" {
  name = "${var.environment}-event-publisher-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = [
            "lambda.amazonaws.com",
            "ecs-tasks.amazonaws.com"
          ]
        }
      }
    ]
  })

  tags = {
    Environment = var.environment
    Purpose     = "event-publishing"
  }
}

# Policy allowing event publishing
resource "aws_iam_role_policy" "event_publisher" {
  name = "${var.environment}-event-publisher-policy"
  role = aws_iam_role.event_publisher.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "events:PutEvents"
        ]
        Resource = aws_cloudwatch_event_bus.main.arn
      },
      {
        Effect = "Allow"
        Action = [
          "schemas:DescribeRegistry",
          "schemas:DescribeSchema",
          "schemas:GetDiscoveredSchema"
        ]
        Resource = [
          aws_schemas_registry.events.arn,
          "${aws_schemas_registry.events.arn}/*"
        ]
      }
    ]
  })
}

# Basic Lambda execution policy attachment
resource "aws_iam_role_policy_attachment" "event_publisher_basic" {
  role       = aws_iam_role.event_publisher.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# IAM role for Lambda functions that process events
resource "aws_iam_role" "event_processor" {
  name = "${var.environment}-event-processor-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Environment = var.environment
    Purpose     = "event-processing"
  }
}

# Policy for event processors
resource "aws_iam_role_policy" "event_processor" {
  name = "${var.environment}-event-processor-policy"
  role = aws_iam_role.event_processor.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "events:PutEvents"
        ]
        Resource = aws_cloudwatch_event_bus.main.arn
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.event_dlq.arn
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = [
          "arn:aws:s3:::${var.audio_bucket}/*",
          "arn:aws:s3:::${var.document_bucket}/*",
          "arn:aws:s3:::${var.video_bucket}/*",
          "arn:aws:s3:::${var.transcript_bucket}/*"
        ]
      }
    ]
  })
}

# Basic Lambda execution policy attachment
resource "aws_iam_role_policy_attachment" "event_processor_basic" {
  role       = aws_iam_role.event_processor.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# EventBridge permissions to invoke Lambda targets (only for existing functions)
resource "aws_lambda_permission" "eventbridge_invoke" {
  for_each = {
    for k, v in {
      event_logger           = var.event_logger_lambda_arn
      dead_letter_processor  = var.dead_letter_processor_lambda_arn
      transcription_handler  = var.transcription_handler_lambda_arn
      search_indexer        = var.search_indexer_lambda_arn
      notification_handler  = var.notification_handler_lambda_arn
    } : k => v if v != ""
  }

  statement_id  = "AllowExecutionFromEventBridge-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = each.value
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_bus.main.arn
}

# Role for EventBridge to send failed events to DLQ
resource "aws_iam_role" "eventbridge_dlq" {
  name = "${var.environment}-eventbridge-dlq-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Environment = var.environment
    Purpose     = "eventbridge-dlq"
  }
}

# Policy for EventBridge to send to DLQ
resource "aws_iam_role_policy" "eventbridge_dlq" {
  name = "${var.environment}-eventbridge-dlq-policy"
  role = aws_iam_role.eventbridge_dlq.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage"
        ]
        Resource = aws_sqs_queue.event_dlq.arn
      }
    ]
  })
}

# Output the role ARNs for use in other services
output "event_publisher_role_arn" {
  value       = aws_iam_role.event_publisher.arn
  description = "ARN of the IAM role for publishing events"
}

output "event_processor_role_arn" {
  value       = aws_iam_role.event_processor.arn
  description = "ARN of the IAM role for processing events"
}

output "event_bus_name" {
  value       = aws_cloudwatch_event_bus.main.name
  description = "Name of the EventBridge event bus"
}

output "event_bus_arn" {
  value       = aws_cloudwatch_event_bus.main.arn
  description = "ARN of the EventBridge event bus"
}