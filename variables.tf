variable "aws_region" {
  description = "The AWS region where resources will be provisioned"
  type        = string
  default     = "eu-central-1" # Frankfurt region - default for German / European Fintech (Scalable Capital)
}

variable "environment" {
  description = "Deployment environment (e.g., dev, staging, prod)"
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Project identifier used in resource naming and tags"
  type        = string
  default     = "scalable-ai-telemetry"
}

variable "openai_api_key" {
  description = "OpenAI API Key to be stored in AWS Secrets Manager (sensitive)"
  type        = string
  sensitive   = true
  default     = "sk-placeholder-key-for-terraform-setup"
}

variable "anthropic_api_key" {
  description = "Anthropic API Key to be stored in AWS Secrets Manager (sensitive)"
  type        = string
  sensitive   = true
  default     = "sk-ant-placeholder-key-for-terraform-setup"
}
