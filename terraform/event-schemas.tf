# Event Schema Registry Configuration
# Registers and manages event schemas for validation and discovery

# Create schema registry
resource "aws_schemas_registry" "events" {
  name        = "${var.environment}-event-schemas"
  description = "Schema registry for application events"

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# Schema: Audio Uploaded
resource "aws_schemas_schema" "audio_uploaded" {
  name          = "AudioUploaded"
  registry_name = aws_schemas_registry.events.name
  type          = "JSONSchemaDraft4"
  description   = "Schema for audio file upload events"

  content = jsonencode({
    "$schema" = "http://json-schema.org/draft-04/schema#"
    title     = "AudioUploaded"
    type      = "object"
    properties = {
      version = {
        type = "string"
        enum = ["1.0"]
      }
      source = {
        type = "string"
        enum = ["custom.upload-service"]
      }
      "detail-type" = {
        type = "string"
        enum = ["Audio Uploaded"]
      }
      detail = {
        type = "object"
        properties = {
          userId = {
            type = "string"
          }
          fileId = {
            type    = "string"
            pattern = "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
          }
          s3Location = {
            type = "object"
            properties = {
              bucket = { type = "string" }
              key    = { type = "string" }
            }
            required = ["bucket", "key"]
          }
          metadata = {
            type = "object"
            properties = {
              format      = { type = "string" }
              size        = { type = "number" }
              contentType = { type = "string" }
            }
            required = ["format", "size", "contentType"]
          }
        }
        required = ["userId", "fileId", "s3Location", "metadata"]
      }
    }
    required = ["version", "source", "detail-type", "detail"]
  })

  tags = {
    Version = "1.0"
    Type    = "audio"
  }
}

# Schema: Document Uploaded
resource "aws_schemas_schema" "document_uploaded" {
  name          = "DocumentUploaded"
  registry_name = aws_schemas_registry.events.name
  type          = "JSONSchemaDraft4"
  description   = "Schema for document file upload events"

  content = jsonencode({
    "$schema" = "http://json-schema.org/draft-04/schema#"
    title     = "DocumentUploaded"
    type      = "object"
    properties = {
      version = {
        type = "string"
        enum = ["1.0"]
      }
      source = {
        type = "string"
        enum = ["custom.upload-service"]
      }
      "detail-type" = {
        type = "string"
        enum = ["Document Uploaded"]
      }
      detail = {
        type = "object"
        properties = {
          userId = {
            type = "string"
          }
          fileId = {
            type    = "string"
            pattern = "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
          }
          s3Location = {
            type = "object"
            properties = {
              bucket = { type = "string" }
              key    = { type = "string" }
            }
            required = ["bucket", "key"]
          }
          metadata = {
            type = "object"
            properties = {
              format      = { type = "string" }
              size        = { type = "number" }
              contentType = { type = "string" }
            }
            required = ["format", "size", "contentType"]
          }
        }
        required = ["userId", "fileId", "s3Location", "metadata"]
      }
    }
    required = ["version", "source", "detail-type", "detail"]
  })

  tags = {
    Version = "1.0"
    Type    = "document"
  }
}

# Schema: Video Uploaded
resource "aws_schemas_schema" "video_uploaded" {
  name          = "VideoUploaded"
  registry_name = aws_schemas_registry.events.name
  type          = "JSONSchemaDraft4"
  description   = "Schema for video file upload events"

  content = jsonencode({
    "$schema" = "http://json-schema.org/draft-04/schema#"
    title     = "VideoUploaded"
    type      = "object"
    properties = {
      version = {
        type = "string"
        enum = ["1.0"]
      }
      source = {
        type = "string"
        enum = ["custom.upload-service"]
      }
      "detail-type" = {
        type = "string"
        enum = ["Video Uploaded"]
      }
      detail = {
        type = "object"
        properties = {
          userId = {
            type = "string"
          }
          fileId = {
            type    = "string"
            pattern = "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
          }
          s3Location = {
            type = "object"
            properties = {
              bucket = { type = "string" }
              key    = { type = "string" }
            }
            required = ["bucket", "key"]
          }
          metadata = {
            type = "object"
            properties = {
              format      = { type = "string" }
              size        = { type = "number" }
              contentType = { type = "string" }
            }
            required = ["format", "size", "contentType"]
          }
        }
        required = ["userId", "fileId", "s3Location", "metadata"]
      }
    }
    required = ["version", "source", "detail-type", "detail"]
  })

  tags = {
    Version = "1.0"
    Type    = "video"
  }
}

# Schema: Transcription Completed
resource "aws_schemas_schema" "transcription_completed" {
  name          = "TranscriptionCompleted"
  registry_name = aws_schemas_registry.events.name
  type          = "JSONSchemaDraft4"
  description   = "Schema for transcription completion events"

  content = jsonencode({
    "$schema" = "http://json-schema.org/draft-04/schema#"
    title     = "TranscriptionCompleted"
    type      = "object"
    properties = {
      version = {
        type = "string"
        enum = ["1.0"]
      }
      source = {
        type = "string"
        enum = ["custom.transcription-service"]
      }
      "detail-type" = {
        type = "string"
        enum = ["Transcription Completed"]
      }
      detail = {
        type = "object"
        properties = {
          userId = {
            type = "string"
          }
          fileId = {
            type    = "string"
            pattern = "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
          }
          jobId = {
            type    = "string"
            pattern = "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
          }
          status = {
            type = "string"
            enum = ["completed", "failed", "partial"]
          }
          sourceAudio = {
            type = "object"
            properties = {
              bucket = { type = "string" }
              key    = { type = "string" }
            }
            required = ["bucket", "key"]
          }
          transcriptLocation = {
            type = "object"
            properties = {
              bucket  = { type = "string" }
              textKey = { type = "string" }
              jsonKey = { type = "string" }
            }
            required = ["bucket", "textKey", "jsonKey"]
          }
          completedAt = {
            type   = "string"
            format = "date-time"
          }
        }
        required = ["userId", "fileId", "jobId", "status", "sourceAudio", "completedAt"]
      }
    }
    required = ["version", "source", "detail-type", "detail"]
  })

  tags = {
    Version = "1.0"
    Type    = "transcription"
  }
}

# Schema: User Registered
resource "aws_schemas_schema" "user_registered" {
  name          = "UserRegistered"
  registry_name = aws_schemas_registry.events.name
  type          = "JSONSchemaDraft4"
  description   = "Schema for user registration events"

  content = jsonencode({
    "$schema" = "http://json-schema.org/draft-04/schema#"
    title     = "UserRegistered"
    type      = "object"
    properties = {
      version = {
        type = "string"
        enum = ["1.0"]
      }
      source = {
        type = "string"
        enum = ["custom.auth-service"]
      }
      "detail-type" = {
        type = "string"
        enum = ["User Registered"]
      }
      detail = {
        type = "object"
        properties = {
          userId = {
            type = "string"
          }
          email = {
            type   = "string"
            format = "email"
          }
          username = {
            type = "string"
          }
          registrationMethod = {
            type = "string"
            enum = ["email", "social-google", "social-facebook", "social-apple", "saml", "admin-created"]
          }
          registeredAt = {
            type   = "string"
            format = "date-time"
          }
        }
        required = ["userId", "email", "username", "registrationMethod", "registeredAt"]
      }
    }
    required = ["version", "source", "detail-type", "detail"]
  })

  tags = {
    Version = "1.0"
    Type    = "user"
  }
}

# Schema discoverer (optional - discovers schemas from events automatically)
resource "aws_schemas_discoverer" "main" {
  source_arn  = aws_cloudwatch_event_bus.main.arn
  description = "Automatically discover schemas from events"

  tags = {
    Environment = var.environment
  }
}