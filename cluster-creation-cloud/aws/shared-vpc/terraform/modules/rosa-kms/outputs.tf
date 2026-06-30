# ROSA HCP KMS Module - Outputs

output "kms_key_arn" {
  description = "ARN of the KMS key"
  value       = aws_kms_key.rosa.arn
}

output "kms_key_id" {
  description = "ID of the KMS key"
  value       = aws_kms_key.rosa.key_id
}

output "kms_alias_arn" {
  description = "ARN of the KMS alias"
  value       = aws_kms_alias.rosa.arn
}
