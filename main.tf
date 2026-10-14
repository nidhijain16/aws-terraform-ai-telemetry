terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }

  # Production Best Practice: Remote State in S3 with DynamoDB Locking
  # backend "s3" {
  #   bucket         = "scalable-terraform-state-prod"
  #   key            = "ai-platform/terraform.tfstate"
  #   region         = "eu-central-1"
  #   dynamodb_table = "terraform-state-lock"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = "AI-Platform-Engineering"
      CostCenter  = "Fintech-Innovation"
    }
  }
}

# Unique suffix generator to prevent S3 bucket naming collisions globally
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# ==============================================================================
# 1. AWS S3: AI AGENT ARTIFACTS & TELEMETRY DATA STORE
# ==============================================================================
resource "aws_s3_bucket" "ai_artifacts" {
  bucket        = "${var.project_name}-artifacts-${var.environment}-${random_string.suffix.result}"
  force_destroy = var.environment != "prod" # Protect production data from accidental deletion

  tags = {
    Name        = "AI Agent Artifacts and Observability Bucket"
    DataPrivacy = "InternalTelemetry"
  }
}

# Ensure object versioning is enabled for auditability, rollback, and compliance (BaFin / SOC2)
resource "aws_s3_bucket_versioning" "ai_artifacts_versioning" {
  bucket = aws_s3_bucket.ai_artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Server-Side Encryption (SSE-S3 AES-256) at rest
resource "aws_s3_bucket_server_side_encryption_configuration" "ai_artifacts_encryption" {
  bucket = aws_s3_bucket.ai_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Strict Public Access Block (Mandatory for Financial Services / BaFin compliance)
resource "aws_s3_bucket_public_access_block" "ai_artifacts_pab" {
  bucket = aws_s3_bucket.ai_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle rule to manage data storage costs (FinOps best practice)
resource "aws_s3_bucket_lifecycle_configuration" "ai_artifacts_lifecycle" {
  bucket = aws_s3_bucket.ai_artifacts.id

  rule {
    id     = "archive-old-telemetry"
    status = "Enabled"

    filter {
      prefix = "telemetry/"
    }

    transition {
      days          = 60
      storage_class = "STANDARD_IA" # Infrequent Access
    }

    transition {
      days          = 180
      storage_class = "GLACIER" # Long term regulatory retention
    }

    expiration {
      days = 730 # 2-year retention for telemetry logs
    }
  }
}

# ==============================================================================
# 2. AWS SECRETS MANAGER: LLM API CREDENTIALS (OPENAI / ANTHROPIC)
# ==============================================================================
resource "aws_secretsmanager_secret" "llm_credentials" {
  name                    = "${var.project_name}/llm-credentials-${var.environment}"
  description             = "Encrypted API keys for LLM providers (OpenAI, Anthropic) managed by AI Platform"
  recovery_window_in_days = var.environment == "prod" ? 30 : 0

  tags = {
    Classification = "Confidential"
    Compliance     = "BaFin-MaRisk"
  }
}

resource "aws_secretsmanager_secret_version" "llm_credentials_version" {
  secret_id = aws_secretsmanager_secret.llm_credentials.id
  secret_string = jsonencode({
    OPENAI_API_KEY    = var.openai_api_key
    ANTHROPIC_API_KEY = var.anthropic_api_key
  })
}

# ==============================================================================
# 3. IAM LEAST-PRIVILEGE EXECUTION ROLE FOR AI SERVICES (ECS / LAMBDA / POD)
# ==============================================================================
# Assume Role Policy document: restricts which compute entity can assume this identity
data "aws_iam_policy_document" "ai_service_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com", "lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ai_service_role" {
  name               = "${var.project_name}-execution-role-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.ai_service_assume_role.json
  description        = "Least privilege IAM execution role for AI telemetry & agent services"
}

# Least-Privilege Policy: ONLY grants access to the specific bucket and specific secret
data "aws_iam_policy_document" "ai_service_least_privilege" {
  # S3 Permissions: Scoped strictly to the created bucket and its object paths
  statement {
    sid    = "AllowS3ObjectRWOnAIBucketOnly"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.ai_artifacts.arn,
      "${aws_s3_bucket.ai_artifacts.arn}/*"
    ]
  }

  # Secrets Manager Permissions: Scoped strictly to the LLM secret ARN
  statement {
    sid    = "AllowGetLLMCredentialsOnly"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue"
    ]
    resources = [
      aws_secretsmanager_secret.llm_credentials.arn
    ]
  }

  # CloudWatch Logging Permissions for Observability
  statement {
    sid    = "AllowCloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }
}

resource "aws_iam_policy" "ai_service_policy" {
  name        = "${var.project_name}-least-privilege-policy-${var.environment}"
  description = "Granular least-privilege policy for S3 telemetry and Secrets Manager LLM keys"
  policy      = data.aws_iam_policy_document.ai_service_least_privilege.json
}

resource "aws_iam_role_policy_attachment" "ai_service_attachment" {
  role       = aws_iam_role.ai_service_role.name
  policy_arn = aws_iam_policy.ai_service_policy.arn
}
