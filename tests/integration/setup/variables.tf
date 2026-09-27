variable "name_prefix" {
  description = "Prefix of the disposable origin bucket name; a random suffix is appended so concurrent runs never collide. Include only characters valid in a bucket name."
  type        = string
  default     = "cloudfront-it"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,48}[a-z0-9])?$", var.name_prefix))
    error_message = "name_prefix must be 1-50 lowercase alphanumeric characters or hyphens, so the suffixed name stays within 63 characters."
  }
}

variable "tags" {
  description = "Tags applied to the origin bucket in addition to the identifying defaults."
  type        = map(string)
  default     = {}
}
