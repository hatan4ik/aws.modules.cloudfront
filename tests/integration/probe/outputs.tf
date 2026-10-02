output "status_code" {
  description = "HTTP status code CloudFront returned for the probe object."
  value       = data.http.probe.status_code
}

output "body" {
  description = "Response body CloudFront returned for the probe object."
  value       = data.http.probe.response_body
}

output "bucket_policy_attached" {
  description = "Whether this probe ran with the module's bucket-policy statement attached."
  value       = length(aws_s3_bucket_policy.origin) == 1
}
