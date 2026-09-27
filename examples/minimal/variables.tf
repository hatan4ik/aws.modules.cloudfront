variable "region" {
  description = "AWS region the distribution and its bucket-owning provider are configured against. CloudFront itself is global; this only affects which region Terraform's default provider talks to."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Human-readable identifier for the distribution: becomes its comment, the Origin Access Control's name, and the default Name tag."
  type        = string
  default     = "static-site-minimal"
}

variable "bucket_name" {
  description = "Name of the existing private S3 bucket to serve, such as aws.modules.s3's aws_s3_bucket.this.bucket output."
  type        = string
}

variable "bucket_regional_domain_name" {
  description = "Regional domain name of that bucket, such as aws.modules.s3's aws_s3_bucket.this.bucket_regional_domain_name output."
  type        = string
}
