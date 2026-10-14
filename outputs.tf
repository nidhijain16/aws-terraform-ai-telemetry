output "s3_bucket_name" {
  description = "The name of the S3 bucket created for telemetry and model artifacts"
  value       = aws_s3_bucket.ai_artifacts.id
}

output "s3_bucket_arn" {
  description = "The ARN of the S3 bucket"
  value       = aws_s3_bucket.ai_artifacts.arn
}

output "secrets_manager_secret_arn" {
  description = "The ARN of the Secrets Manager secret storing LLM credentials"
  value       = aws_secretsmanager_secret.llm_credentials.arn
}

output "secrets_manager_secret_name" {
  description = "The Name of the Secrets Manager secret"
  value       = aws_secretsmanager_secret.llm_credentials.name
}

output "iam_execution_role_arn" {
  description = "The ARN of the IAM Execution Role with least privilege access"
  value       = aws_iam_role.ai_service_role.arn
}

output "iam_execution_role_name" {
  description = "The Name of the IAM Execution Role"
  value       = aws_iam_role.ai_service_role.name
}
