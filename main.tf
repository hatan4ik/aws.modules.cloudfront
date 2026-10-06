# One CloudFront distribution serving one private S3 origin (ADR 0004's
# static delivery path), the Origin Access Control it reads through, and the
# rendered statement the caller merges into that bucket's own policy.

# The one documented exception to the no-data-source rule: the origin
# bucket's partition is needed only to render required_bucket_policy_json's
# Resource ARN, and nothing else in the interface can supply it. Skipped
# when the caller passes partition.
data "aws_partition" "current" {
  count = var.partition == null ? 1 : 0
}

resource "aws_cloudfront_origin_access_control" "this" {
  name                              = var.name
  description                       = "OAC for ${var.name}, restricting s3:GetObject on the origin bucket to this distribution's own SourceArn."
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = var.name
  default_root_object = var.default_root_object
  price_class         = var.price_class
  aliases             = var.aliases
  web_acl_id          = var.web_acl_arn

  origin {
    domain_name              = var.origin.bucket_regional_domain_name
    origin_id                = var.origin.bucket_name
    origin_path              = var.origin.origin_path
    origin_access_control_id = aws_cloudfront_origin_access_control.this.id
  }

  default_cache_behavior {
    target_origin_id           = var.origin.bucket_name
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = sort(tolist(local.default_cache_behavior.allowed_methods))
    cached_methods             = sort(tolist(local.default_cache_behavior.cached_methods))
    cache_policy_id            = local.default_cache_behavior.cache_policy_id
    response_headers_policy_id = local.default_cache_behavior.response_headers_policy_id
    compress                   = local.default_cache_behavior.compress
  }

  # Iterates a list, so behaviors render in the caller's declared order,
  # which is the order CloudFront evaluates them in (first match wins).
  dynamic "ordered_cache_behavior" {
    for_each = local.cache_behaviors

    content {
      path_pattern               = ordered_cache_behavior.value.path_pattern
      target_origin_id           = var.origin.bucket_name
      viewer_protocol_policy     = "redirect-to-https"
      allowed_methods            = sort(tolist(ordered_cache_behavior.value.allowed_methods))
      cached_methods             = sort(tolist(ordered_cache_behavior.value.cached_methods))
      cache_policy_id            = ordered_cache_behavior.value.cache_policy_id
      response_headers_policy_id = ordered_cache_behavior.value.response_headers_policy_id
      compress                   = ordered_cache_behavior.value.compress
    }
  }

  dynamic "custom_error_response" {
    for_each = var.custom_error_responses

    content {
      error_code            = custom_error_response.value.error_code
      response_code         = custom_error_response.value.response_code
      response_page_path    = custom_error_response.value.response_page_path
      error_caching_min_ttl = custom_error_response.value.error_caching_min_ttl
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = var.geo_restriction.restriction_type
      locations        = sort(tolist(var.geo_restriction.locations))
    }
  }

  # Exactly one of the two branches below ever produces a block: the default
  # *.cloudfront.net certificate when there are no aliases, or the caller's
  # us-east-1 ACM certificate with SNI when there are. CloudFront rejects a
  # minimum_protocol_version other than its own fixed value alongside the
  # default certificate, so that argument is only threaded through the
  # custom-domain branch.
  dynamic "viewer_certificate" {
    for_each = local.has_aliases ? [] : [true]

    content {
      cloudfront_default_certificate = true
    }
  }

  dynamic "viewer_certificate" {
    for_each = local.has_aliases ? [true] : []

    content {
      acm_certificate_arn      = var.viewer_certificate_arn
      ssl_support_method       = "sni-only"
      minimum_protocol_version = var.minimum_protocol_version
    }
  }

  dynamic "logging_config" {
    for_each = var.logging == null ? [] : [var.logging]

    content {
      bucket          = logging_config.value.bucket_domain_name
      prefix          = logging_config.value.prefix
      include_cookies = false
    }
  }

  tags = local.tags

  lifecycle {
    precondition {
      condition     = local.partition == "aws"
      error_message = "This module supports only the standard aws partition. CloudFront in aws-cn supports neither Origin Access Control, ACM viewer certificates, nor WAF, and aws-us-gov has no CloudFront; hosted_zone_id would also be wrong outside aws."
    }

    precondition {
      condition     = local.has_aliases ? var.viewer_certificate_arn != null : true
      error_message = "viewer_certificate_arn is required when aliases is non-empty: CloudFront cannot serve a custom domain with only the default *.cloudfront.net certificate."
    }

    precondition {
      condition     = local.has_aliases ? true : var.viewer_certificate_arn == null
      error_message = "viewer_certificate_arn must be unset when aliases is empty: with no custom domain the default *.cloudfront.net certificate is used, and a certificate ARN with no aliases to serve it for is almost always a mistake."
    }
  }
}
