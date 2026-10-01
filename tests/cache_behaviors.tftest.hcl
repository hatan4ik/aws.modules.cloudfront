mock_provider "aws" {}

variables {
  name = "static-site"
  origin = {
    bucket_name                 = "static-site-origin"
    bucket_regional_domain_name = "static-site-origin.s3.us-east-1.amazonaws.com"
  }
  web_acl_arn = "arn:aws:wafv2:us-east-1:123456789012:global/webacl/static-site/11111111-1111-1111-1111-111111111111"
  logging = {
    bucket_domain_name = "static-site-logs.s3.amazonaws.com"
  }
}

run "renders_one_ordered_cache_behavior_per_path_pattern" {
  command = plan

  variables {
    cache_behaviors = {
      "/api/*" = {
        allowed_methods = ["GET", "HEAD", "OPTIONS"]
      }
      "/static/*" = {}
    }
  }

  assert {
    condition     = length(aws_cloudfront_distribution.this.ordered_cache_behavior) == 2
    error_message = "One ordered_cache_behavior must render per cache_behaviors key."
  }

  assert {
    condition     = toset([for behavior in aws_cloudfront_distribution.this.ordered_cache_behavior : behavior.path_pattern]) == toset(["/api/*", "/static/*"])
    error_message = "Each rendered behavior's path_pattern must be its cache_behaviors key."
  }

  assert {
    condition     = [for behavior in aws_cloudfront_distribution.this.ordered_cache_behavior : toset(behavior.allowed_methods) if behavior.path_pattern == "/api/*"][0] == toset(["GET", "HEAD", "OPTIONS"])
    error_message = "The /api/* behavior must render its declared allowed_methods."
  }

  assert {
    condition     = [for behavior in aws_cloudfront_distribution.this.ordered_cache_behavior : behavior.cache_policy_id if behavior.path_pattern == "/static/*"][0] == "658327ea-f89d-4fab-a63d-7e88639e58f6"
    error_message = "A cache_behaviors entry with no cache_policy_id must default to the managed CachingOptimized policy."
  }

  assert {
    condition     = alltrue([for behavior in aws_cloudfront_distribution.this.ordered_cache_behavior : behavior.target_origin_id == "static-site-origin" && behavior.viewer_protocol_policy == "redirect-to-https" && behavior.compress == true])
    error_message = "Every ordered cache behavior must target the single origin, redirect to HTTPS, and compress by default."
  }
}

run "honours_a_caller_supplied_cache_policy_id" {
  command = plan

  variables {
    cache_behaviors = {
      "/api/*" = {
        cache_policy_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
        compress        = false
      }
    }
  }

  assert {
    condition     = [for behavior in aws_cloudfront_distribution.this.ordered_cache_behavior : behavior.cache_policy_id][0] == "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    error_message = "A caller-supplied cache_policy_id must not be replaced by the managed default."
  }

  assert {
    condition     = [for behavior in aws_cloudfront_distribution.this.ordered_cache_behavior : behavior.compress][0] == false
    error_message = "compress = false must be honoured."
  }
}

run "rejects_a_wildcard_path_pattern_key" {
  command = plan

  variables {
    cache_behaviors = {
      "*" = {}
    }
  }

  expect_failures = [var.cache_behaviors]
}
