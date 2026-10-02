variable "bucket_name" {
  description = "Name of the fixture origin bucket the policy is attached to."
  type        = string
}

variable "bucket_policy_statement_json" {
  description = "The module under test's required_bucket_policy_json output: one IAM policy statement, as JSON."
  type        = string
}

variable "attach_bucket_policy" {
  description = "true attaches bucket_policy_statement_json to the bucket (and waits settle_seconds) before probing; false probes with no bucket policy at all."
  type        = bool
}

variable "url" {
  description = "HTTPS URL of the probe object, served through the distribution under test."
  type        = string
}

variable "settle_seconds" {
  description = "Seconds to wait after attaching the policy before probing. Covers S3 bucket-policy propagation and CloudFront's default 10 second caching of the earlier 403 for the same object."
  type        = number
  default     = 90
}
