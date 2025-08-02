# Terraform Variables for EventBridge Infrastructure

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "eventbridge-orchestrator"
}

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-2"
}

variable "event_bus_name" {
  description = "Name of the EventBridge custom bus"
  type        = string
  default     = "dev-application-events"
}

# S3 Bucket Variables
variable "audio_bucket" {
  description = "S3 bucket for audio uploads"
  type        = string
  default     = "audio-uploads-dev"
}

variable "document_bucket" {
  description = "S3 bucket for document uploads"
  type        = string
  default     = "document-uploads-dev"
}

variable "video_bucket" {
  description = "S3 bucket for video uploads"
  type        = string
  default     = "video-uploads-dev"
}

variable "transcript_bucket" {
  description = "S3 bucket for transcription outputs"
  type        = string
  default     = "transcription-outputs-dev"
}

# Lambda Function ARNs (provided by service teams)
variable "event_logger_lambda_arn" {
  description = "ARN of the event logger Lambda function"
  type        = string
  default     = ""  # Set via terraform.tfvars or environment
}

variable "dead_letter_processor_lambda_arn" {
  description = "ARN of the dead letter processor Lambda function"
  type        = string
  default     = ""  # Set via terraform.tfvars or environment
}

variable "transcription_handler_lambda_arn" {
  description = "ARN of the transcription handler Lambda function"
  type        = string
  default     = ""  # Set via terraform.tfvars or environment
}

variable "search_indexer_lambda_arn" {
  description = "ARN of the search indexer Lambda function"
  type        = string
  default     = ""  # Set via terraform.tfvars or environment
}

variable "notification_handler_lambda_arn" {
  description = "ARN of the notification handler Lambda function"
  type        = string
  default     = ""  # Set via terraform.tfvars or environment
}

# Tags
variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    ManagedBy = "Terraform"
    Service   = "EventBridge"
  }
}