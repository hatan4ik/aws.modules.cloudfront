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

output "probe_object_key" {
  description = "Key of the known object the smoke suite fetches through the distribution."
  value       = aws_s3_object.probe.key
}

output "probe_object_body" {
  description = "Exact body of the probe object, which a successful fetch through the distribution must return."
  value       = local.probe_body
}
