variable "region" {
  description = "AWS region Terraform's default provider talks to."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Human-readable identifier for the distribution."
  type        = string
  default     = "spa-with-error-rewrites"
}

variable "bucket_name" {
  description = "Name of the existing private S3 bucket holding the single-page application's built assets."
  type        = string
}

variable "bucket_regional_domain_name" {
  description = "Regional domain name of that bucket."
  type        = string
}
