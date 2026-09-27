output "bucket_name" {
  description = "Name of the disposable origin bucket."
  value       = aws_s3_bucket.origin.bucket
}

output "bucket_regional_domain_name" {
  description = "Regional domain name of the disposable origin bucket, the module under test's origin.bucket_regional_domain_name input."
  value       = aws_s3_bucket.origin.bucket_regional_domain_name
}

output "bucket_arn" {
  description = "ARN of the disposable origin bucket, used by the smoke suite to attach the module's required_bucket_policy_json statement."
  value       = aws_s3_bucket.origin.arn
}

output "tags" {
  description = "Identifying tags applied to the origin bucket."
  value       = local.tags
}
