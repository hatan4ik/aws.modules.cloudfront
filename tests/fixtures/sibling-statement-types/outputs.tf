output "s3_bucket_policy_statements" {
  description = "s3_bucket_policy_statements after conversion to aws.modules.s3's type, optional defaults applied."
  value       = var.s3_bucket_policy_statements
}

output "kms_policy_statements" {
  description = "kms_policy_statements after conversion to aws.modules.kms's type, optional defaults applied."
  value       = var.kms_policy_statements
}
