mock_provider "aws" {}

variables {
  name = "static-site"
  origin = {
    bucket_name                 = "static-site-origin"
    bucket_regional_domain_name = "static-site-origin.s3.us-east-1.amazonaws.com"
  }
  web_acl_arn = "arn:aws:wafv2:global:123456789012:global/webacl/static-site/11111111-1111-1111-1111-111111111111"
  logging = {
    bucket_domain_name = "static-site-logs.s3.amazonaws.com"
  }
  tags = { Environment = "test", Owner = "platform" }
}

run "creates_a_distribution_with_secure_defaults" {
  command = plan

  assert {
    condition     = aws_cloudfront_distribution.this.enabled == true && aws_cloudfront_distribution.this.is_ipv6_enabled == true
    error_message = "The distribution must be enabled with IPv6 by default."
  }

  assert {
    condition     = aws_cloudfront_distribution.this.comment == "static-site" && aws_cloudfront_distribution.this.default_root_object == "index.html" && aws_cloudfront_distribution.this.price_class == "PriceClass_100"
    error_message = "comment must come from name, and default_root_object/price_class must default to index.html/PriceClass_100."
  }

  assert {
    condition     = length(aws_cloudfront_distribution.this.aliases) == 0
    error_message = "No aliases must be set by default."
  }

  assert {
    condition     = aws_cloudfront_distribution.this.viewer_certificate[0].cloudfront_default_certificate == true && aws_cloudfront_distribution.this.viewer_certificate[0].acm_certificate_arn == null
    error_message = "With no aliases the default CloudFront certificate must be used, with no ACM certificate attached."
  }

  assert {
    condition     = aws_cloudfront_distribution.this.default_cache_behavior[0].cache_policy_id == "658327ea-f89d-4fab-a63d-7e88639e58f6" && aws_cloudfront_distribution.this.default_cache_behavior[0].compress == true
    error_message = "The default cache behavior must use the managed CachingOptimized policy and compression on by default."
  }

  assert {
    condition     = toset(aws_cloudfront_distribution.this.default_cache_behavior[0].allowed_methods) == toset(["GET", "HEAD"]) && toset(aws_cloudfront_distribution.this.default_cache_behavior[0].cached_methods) == toset(["GET", "HEAD"])
    error_message = "Default cache behavior methods must default to GET and HEAD."
  }

  assert {
    condition     = aws_cloudfront_distribution.this.restrictions[0].geo_restriction[0].restriction_type == "none"
    error_message = "geo_restriction must default to none."
  }

  assert {
    condition     = length(aws_cloudfront_distribution.this.ordered_cache_behavior) == 0 && length(aws_cloudfront_distribution.this.custom_error_response) == 0
    error_message = "No ordered cache behaviors or custom error responses may render unless declared."
  }

  assert {
    condition     = aws_cloudfront_distribution.this.web_acl_id == var.web_acl_arn
    error_message = "web_acl_id must pass through the declared Web ACL ARN."
  }

  assert {
    condition     = length(aws_cloudfront_distribution.this.logging_config) == 1 && aws_cloudfront_distribution.this.logging_config[0].bucket == "static-site-logs.s3.amazonaws.com" && aws_cloudfront_distribution.this.logging_config[0].include_cookies == false
    error_message = "logging_config must render from the logging input with include_cookies false."
  }

  assert {
    condition     = aws_cloudfront_origin_access_control.this.name == "static-site" && aws_cloudfront_origin_access_control.this.signing_behavior == "always" && aws_cloudfront_origin_access_control.this.signing_protocol == "sigv4" && aws_cloudfront_origin_access_control.this.origin_access_control_origin_type == "s3"
    error_message = "The Origin Access Control must be named after the distribution and use sigv4 always signing for S3."
  }

  assert {
    condition     = tolist(aws_cloudfront_distribution.this.origin)[0].domain_name == "static-site-origin.s3.us-east-1.amazonaws.com" && tolist(aws_cloudfront_distribution.this.origin)[0].origin_id == "static-site-origin" && tolist(aws_cloudfront_distribution.this.origin)[0].origin_path == ""
    error_message = "The origin must be wired from the origin input with no origin_path by default."
  }

  assert {
    condition     = aws_cloudfront_distribution.this.tags["Name"] == "static-site" && aws_cloudfront_distribution.this.tags["Owner"] == "platform" && aws_cloudfront_distribution.this.tags["Environment"] == "test"
    error_message = "Caller tags must be preserved and a Name tag derived from name."
  }

  assert {
    condition     = output.hosted_zone_id == "Z2FDTNDATAQYW2"
    error_message = "hosted_zone_id must be CloudFront's fixed alias-target zone ID."
  }
}

run "scopes_the_origin_to_a_path_when_set" {
  command = plan

  variables {
    origin = {
      bucket_name                 = "static-site-origin"
      bucket_regional_domain_name = "static-site-origin.s3.us-east-1.amazonaws.com"
      origin_path                 = "/site"
    }
  }

  assert {
    condition     = tolist(aws_cloudfront_distribution.this.origin)[0].origin_path == "/site"
    error_message = "origin_path must be passed through to the origin block."
  }
}

run "renders_no_logging_config_when_logging_is_null" {
  command = plan

  variables {
    logging = null
  }

  assert {
    condition     = length(aws_cloudfront_distribution.this.logging_config) == 0
    error_message = "No logging_config block may render when logging is null."
  }

  expect_failures = [check.access_logging_disabled]
}
