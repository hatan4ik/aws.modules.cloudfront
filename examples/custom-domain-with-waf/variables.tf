variable "region" {
  description = "AWS region Terraform's default provider talks to. CloudFront itself is global; the certificate and Web ACL below must still have been created through a separate us-east-1 provider elsewhere, which this example only consumes ARNs from."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Human-readable identifier for the distribution."
  type        = string
  default     = "static-site-custom-domain"
}

variable "bucket_name" {
  description = "Name of the existing private S3 bucket to serve."
  type        = string
}

variable "bucket_regional_domain_name" {
  description = "Regional domain name of that bucket."
  type        = string
}

variable "domain_name" {
  description = "Custom domain the distribution answers to, such as app.example.com."
  type        = string
}

variable "viewer_certificate_arn" {
  description = "ACM certificate ARN for domain_name, requested through a us-east-1 provider (see aws.modules.acm's cloudfront example). Its region segment is validated by the module; that it was actually requested via us-east-1 is not something an ARN string can prove and is the caller's responsibility."
  type        = string
}

variable "web_acl_arn" {
  description = "ARN of a CLOUDFRONT-scope WAFv2 Web ACL (aws.modules.waf's web_acl_arn output with scope = \"CLOUDFRONT\", created through us-east-1), such as arn:aws:wafv2:us-east-1:123456789012:global/webacl/app-example-com/<uuid>. The module validates both the us-east-1 region segment and the global/webacl/ resource segment."
  type        = string
}

variable "access_log_bucket_domain_name" {
  description = "Regional domain name of a separate, caller-owned S3 bucket that receives standard CloudFront access logs. Kept separate from the origin bucket on purpose: logs and served content have different retention and access needs."
  type        = string
}
