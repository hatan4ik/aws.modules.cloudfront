# ---------------------------------------------------------------------------
# Identity
# ---------------------------------------------------------------------------

variable "name" {
  description = "Human-readable identifier for the distribution. CloudFront distributions have no name argument: this value becomes the distribution's comment, the Origin Access Control's name, and the default Name tag. At most 64 characters (the tighter of the two limits it drives) using letters, digits, spaces, dots, underscores, and hyphens."
  type        = string
  nullable    = false

  validation {
    condition     = length(var.name) > 0 && length(var.name) <= 64 && can(regex("^[ \\w.-]+$", var.name))
    error_message = "name must be 1-64 characters of letters, digits, spaces, dots, underscores, and hyphens."
  }
}

# ---------------------------------------------------------------------------
# Origin (one private S3 bucket, read through Origin Access Control)
# ---------------------------------------------------------------------------

variable "origin" {
  description = "The single S3 origin this distribution serves. bucket_name and bucket_regional_domain_name come from the bucket the caller owns (for example aws.modules.s3's aws_s3_bucket.this.bucket and .bucket_regional_domain_name outputs); this module never creates or reaches into that bucket. origin_path, when set, must start with / and not end with /, and scopes both the CloudFront origin path and the required_bucket_policy_json output's Resource to that prefix."
  type = object({
    bucket_name                 = string
    bucket_regional_domain_name = string
    origin_path                 = optional(string, "")
  })
  nullable = false

  validation {
    condition     = length(var.origin.bucket_name) > 0
    error_message = "origin.bucket_name must not be empty."
  }

  validation {
    condition     = length(var.origin.bucket_regional_domain_name) > 0
    error_message = "origin.bucket_regional_domain_name must not be empty."
  }

  validation {
    condition     = var.origin.origin_path == "" ? true : can(regex("^/.*[^/]$", var.origin.origin_path))
    error_message = "origin.origin_path must be empty, or start with / and not end with /, such as /site."
  }
}

variable "partition" {
  description = "AWS partition of the origin bucket's account, used only to render the Resource ARN in required_bucket_policy_json. Only the standard \"aws\" partition is supported: CloudFront in the China Regions (aws-cn) supports neither Origin Access Control (this module's only origin access mechanism), ACM viewer certificates, nor AWS WAF, and AWS GovCloud (US) has no CloudFront, so a distribution this module builds cannot work in either. Any other value is rejected here, and a looked-up partition other than aws fails a precondition. Null reads it through aws_partition; pass \"aws\" to skip the lookup."
  type        = string
  default     = null

  validation {
    condition     = var.partition == null ? true : var.partition == "aws"
    error_message = "partition must be aws (or null to look it up). aws-cn and aws-us-gov are not supported: CloudFront there lacks Origin Access Control, ACM certificates, and WAF (aws-cn) or does not exist (aws-us-gov)."
  }
}

# ---------------------------------------------------------------------------
# Distribution behaviour
# ---------------------------------------------------------------------------

variable "price_class" {
  description = "Edge locations that serve the distribution. PriceClass_100 (the default) is the cheapest: US, Canada, and Europe only. Opt into PriceClass_200 (adds Asia, Africa, Oceania) or PriceClass_All explicitly."
  type        = string
  default     = "PriceClass_100"
  nullable    = false

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.price_class)
    error_message = "price_class must be PriceClass_100, PriceClass_200, or PriceClass_All."
  }
}

variable "default_root_object" {
  description = "Object requested at the distribution root (for example when a viewer requests /). Must not start with /."
  type        = string
  default     = "index.html"
  nullable    = false

  validation {
    condition     = !startswith(var.default_root_object, "/")
    error_message = "default_root_object must not start with /; CloudFront appends it to the request path itself."
  }
}

variable "aliases" {
  description = "Custom domain names (CNAMEs) the distribution answers to, in addition to its own *.cloudfront.net domain. Empty by default, which uses the CloudFront default certificate; a non-empty set requires viewer_certificate_arn."
  type        = set(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for alias in var.aliases : can(regex("^(\\*\\.)?([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", alias))])
    error_message = "Every alias must be a lowercase fully qualified domain name, optionally starting with a wildcard label (*.example.com)."
  }
}

variable "viewer_certificate_arn" {
  description = "ACM certificate ARN presented to viewers for a custom domain. Required when aliases is non-empty and forbidden when it is empty (the default *.cloudfront.net certificate already covers that case). CloudFront only ever reads viewer certificates from us-east-1, regardless of the origin bucket's region or this module's own provider region, so the ARN's region segment is validated here; the certificate itself must actually have been requested through a us-east-1 provider (see aws.modules.acm's cloudfront example) since Terraform cannot inspect where an ARN's resource was created, only what the ARN string says."
  type        = string
  default     = null

  validation {
    condition     = var.viewer_certificate_arn == null ? true : can(regex("^arn:[a-z-]+:acm:us-east-1:[0-9]{12}:certificate/[0-9a-fA-F-]{36}$", var.viewer_certificate_arn))
    error_message = "viewer_certificate_arn must be an ACM certificate ARN in us-east-1 (arn:<partition>:acm:us-east-1:<account>:certificate/<uuid>), the only region CloudFront reads viewer certificates from."
  }
}

variable "minimum_protocol_version" {
  description = "CloudFront security policy (minimum TLS version and ciphers) for viewers when a custom viewer certificate is used (aliases non-empty). Accepts the TLS 1.2+ policies TLSv1.2_2018, TLSv1.2_2019, TLSv1.2_2021 (the default), TLSv1.2_2025, and TLSv1.3_2025 (TLS 1.3 only); policies allowing deprecated TLS 1.0/1.1 are rejected. Ignored when the distribution uses the default certificate, which CloudFront always serves at its own fixed minimum version."
  type        = string
  default     = "TLSv1.2_2021"
  nullable    = false

  validation {
    condition     = contains(["TLSv1.2_2018", "TLSv1.2_2019", "TLSv1.2_2021", "TLSv1.2_2025", "TLSv1.3_2025"], var.minimum_protocol_version)
    error_message = "minimum_protocol_version must be one of TLSv1.2_2018, TLSv1.2_2019, TLSv1.2_2021, TLSv1.2_2025, or TLSv1.3_2025. Policies that allow TLS 1.0 or 1.1 (TLSv1, TLSv1_2016, TLSv1.1_2016) are not accepted."
  }
}

variable "web_acl_arn" {
  description = "ARN of a CLOUDFRONT-scope WAFv2 Web ACL (for example aws.modules.waf's web_acl_arn output with scope = \"CLOUDFRONT\") to associate with the distribution. Optional, but a check block advises setting it: ADR 0004 places a global WAF at every entry layer. AWS issues a CLOUDFRONT-scope Web ACL's ARN as arn:<partition>:wafv2:us-east-1:<account>:global/webacl/<name>/<id>: the region segment is the real region us-east-1 (the only region WAFv2 accepts CLOUDFRONT-scope ACLs from) and \"global\" appears only in the resource segment. Both are validated, so a REGIONAL-scope ARN (regional/webacl/...) or a CLOUDFRONT-shaped ARN naming any other region is rejected at plan time. <name> accepts letters, digits, hyphens, and underscores, the same characters aws.modules.waf and the WAFv2 API allow. See docs/DESIGN.md."
  type        = string
  default     = null

  validation {
    condition     = var.web_acl_arn == null ? true : can(regex("^arn:[a-z-]+:wafv2:us-east-1:[0-9]{12}:global/webacl/[a-zA-Z0-9_-]{1,128}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.web_acl_arn))
    error_message = "web_acl_arn must be a CLOUDFRONT-scope WAFv2 Web ACL ARN as AWS issues it: arn:<partition>:wafv2:us-east-1:<account>:global/webacl/<name>/<id>, where <name> is 1-128 letters, digits, hyphens, or underscores. A REGIONAL-scope ACL ARN (regional/webacl/...) cannot be attached to a CloudFront distribution."
  }
}

variable "geo_restriction" {
  description = "Geographic access restriction. restriction_type none (the default) allows every viewer location; whitelist or blacklist require a non-empty locations set of ISO 3166-1 alpha-2 country codes."
  type = object({
    restriction_type = string
    locations        = optional(set(string), [])
  })
  default  = { restriction_type = "none" }
  nullable = false

  validation {
    condition     = contains(["none", "whitelist", "blacklist"], var.geo_restriction.restriction_type)
    error_message = "geo_restriction.restriction_type must be none, whitelist, or blacklist."
  }

  validation {
    condition     = var.geo_restriction.restriction_type == "none" ? true : length(var.geo_restriction.locations) > 0
    error_message = "geo_restriction.locations must be non-empty when restriction_type is whitelist or blacklist."
  }

  validation {
    condition     = alltrue([for code in var.geo_restriction.locations : can(regex("^[A-Z]{2}$", code))])
    error_message = "Every geo_restriction.locations entry must be an uppercase ISO 3166-1 alpha-2 country code, such as US or DE."
  }
}

variable "logging" {
  description = "Standard CloudFront access logging to a caller-owned S3 bucket. Off (null) by default; a check block advises turning it on. This module does not create or configure the logging bucket's ACLs or bucket-owner-enforced ownership."
  type = object({
    bucket_domain_name = string
    prefix             = optional(string)
  })
  default = null

  validation {
    condition     = var.logging == null ? true : length(var.logging.bucket_domain_name) > 0
    error_message = "logging.bucket_domain_name must not be empty when logging is set."
  }
}

variable "custom_error_responses" {
  description = "SPA-style rewrites of origin error responses, for example serving /index.html with a 200 for a 404 from the origin. error_code is the origin's HTTP status; response_code and response_page_path, when set, together override what the viewer receives; error_caching_min_ttl (default 300) is how long CloudFront caches the error itself."
  type = list(object({
    error_code            = number
    response_code         = optional(number)
    response_page_path    = optional(string)
    error_caching_min_ttl = optional(number, 300)
  }))
  default  = []
  nullable = false

  validation {
    condition     = alltrue([for response in var.custom_error_responses : contains([400, 403, 404, 405, 414, 416, 500, 501, 502, 503, 504], response.error_code)])
    error_message = "Every custom_error_responses[*].error_code must be an HTTP status CloudFront lets you customize: 400, 403, 404, 405, 414, 416, 500, 501, 502, 503, or 504."
  }

  validation {
    condition     = alltrue([for response in var.custom_error_responses : response.response_code == null ? true : (response.response_code >= 200 && response.response_code <= 599)])
    error_message = "Every custom_error_responses[*].response_code, when set, must be a three-digit HTTP status code between 200 and 599."
  }

  validation {
    condition     = alltrue([for response in var.custom_error_responses : (response.response_code == null) == (response.response_page_path == null)])
    error_message = "Every custom_error_responses[*] entry must set both response_code and response_page_path together, or neither."
  }

  validation {
    condition     = alltrue([for response in var.custom_error_responses : response.error_caching_min_ttl >= 0])
    error_message = "Every custom_error_responses[*].error_caching_min_ttl must be zero or greater."
  }
}

# ---------------------------------------------------------------------------
# Cache behaviors
# ---------------------------------------------------------------------------

variable "default_cache_behavior" {
  description = "Cache behaviour for the distribution's default (path_pattern = \"*\") behavior. cache_policy_id null (the default) uses the AWS managed CachingOptimized policy."
  type = object({
    allowed_methods = optional(set(string), ["GET", "HEAD"])
    cached_methods  = optional(set(string), ["GET", "HEAD"])
    cache_policy_id = optional(string)
    compress        = optional(bool, true)
  })
  default  = {}
  nullable = false
}

variable "cache_behaviors" {
  description = "Additional cache behaviors, evaluated before default_cache_behavior. CloudFront uses the FIRST behavior whose path_pattern matches a request, and this list's order is exactly the order CloudFront receives them in: list a narrower pattern (\"/static/images/*\") before a broader one that also matches it (\"/static/*\"), or the narrower one never matches. path_pattern must be non-empty and unique; \"*\" is reserved for default_cache_behavior and rejected here. cache_policy_id null (the default) uses the AWS managed CachingOptimized policy. CloudFront's default quota is 25 cache behaviors per distribution (adjustable through Service Quotas)."
  type = list(object({
    path_pattern    = string
    allowed_methods = optional(set(string), ["GET", "HEAD"])
    cached_methods  = optional(set(string), ["GET", "HEAD"])
    cache_policy_id = optional(string)
    compress        = optional(bool, true)
  }))
  default  = []
  nullable = false

  validation {
    condition     = alltrue([for behavior in var.cache_behaviors : behavior.path_pattern != "*"])
    error_message = "cache_behaviors must not use \"*\" as a path_pattern: it is reserved for default_cache_behavior, configured separately."
  }

  validation {
    condition     = alltrue([for behavior in var.cache_behaviors : length(behavior.path_pattern) > 0])
    error_message = "Every cache_behaviors[*].path_pattern must be non-empty."
  }

  validation {
    condition     = length(distinct([for behavior in var.cache_behaviors : behavior.path_pattern])) == length(var.cache_behaviors)
    error_message = "cache_behaviors path_pattern values must be unique: a second behavior with the same pattern could never match."
  }
}

# ---------------------------------------------------------------------------
# Tags
# ---------------------------------------------------------------------------

variable "tags" {
  description = "Tags applied to the distribution. The module adds a Name tag (from name) only when you do not set one, and never overrides caller tags."
  type        = map(string)
  default     = {}
  nullable    = false
}
