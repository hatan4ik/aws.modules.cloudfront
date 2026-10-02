# The module supports only the standard aws partition (see variables.tf's
# partition), so the mocked partition lookup must return it.
mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
}

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

run "renders_one_ordered_cache_behavior_per_entry" {
  command = plan

  variables {
    cache_behaviors = [
      {
        path_pattern    = "/api/*"
        allowed_methods = ["GET", "HEAD", "OPTIONS"]
      },
      { path_pattern = "/static/*" },
    ]
  }

  assert {
    condition     = length(aws_cloudfront_distribution.this.ordered_cache_behavior) == 2
    error_message = "One ordered_cache_behavior must render per cache_behaviors entry."
  }

  assert {
    condition     = [for behavior in aws_cloudfront_distribution.this.ordered_cache_behavior : behavior.path_pattern] == ["/api/*", "/static/*"]
    error_message = "Each rendered behavior's path_pattern must be its cache_behaviors entry's path_pattern, in list order."
  }

  assert {
    condition     = toset(aws_cloudfront_distribution.this.ordered_cache_behavior[0].allowed_methods) == toset(["GET", "HEAD", "OPTIONS"])
    error_message = "The /api/* behavior must render its declared allowed_methods."
  }

  assert {
    condition     = aws_cloudfront_distribution.this.ordered_cache_behavior[1].cache_policy_id == "658327ea-f89d-4fab-a63d-7e88639e58f6"
    error_message = "A cache_behaviors entry with no cache_policy_id must default to the managed CachingOptimized policy."
  }

  assert {
    condition     = alltrue([for behavior in aws_cloudfront_distribution.this.ordered_cache_behavior : behavior.target_origin_id == "static-site-origin" && behavior.viewer_protocol_policy == "redirect-to-https" && behavior.compress == true])
    error_message = "Every ordered cache behavior must target the single origin, redirect to HTTPS, and compress by default."
  }
}

# CloudFront evaluates ordered_cache_behavior in the order it receives them
# and uses the FIRST pattern that matches. v1.0.0 keyed cache_behaviors by
# path_pattern in a map, and a map's dynamic-block iteration follows lexical
# key order: "/static/*" sorts before "/static/images/*", so the broader
# pattern always rendered first and the narrower one could never match. The
# two runs below declare the same two overlapping patterns in both orders and
# prove the rendered order is the caller's list order in each case, not a
# sort of the patterns.

run "renders_a_narrower_pattern_first_when_the_caller_lists_it_first" {
  command = plan

  variables {
    cache_behaviors = [
      { path_pattern = "/static/images/*", cache_policy_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" },
      { path_pattern = "/static/*" },
    ]
  }

  assert {
    condition     = aws_cloudfront_distribution.this.ordered_cache_behavior[0].path_pattern == "/static/images/*" && aws_cloudfront_distribution.this.ordered_cache_behavior[1].path_pattern == "/static/*"
    error_message = "The more specific /static/images/* must render first when listed first, so CloudFront matches it before the broader /static/*. A lexically sorted order would put /static/* first and shadow it."
  }

  assert {
    condition     = aws_cloudfront_distribution.this.ordered_cache_behavior[0].cache_policy_id == "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" && aws_cloudfront_distribution.this.ordered_cache_behavior[1].cache_policy_id == "658327ea-f89d-4fab-a63d-7e88639e58f6"
    error_message = "Each entry's settings must travel with its own path_pattern when the list is rendered in order."
  }
}

run "renders_patterns_in_list_order_even_against_lexical_order" {
  command = plan

  variables {
    cache_behaviors = [
      { path_pattern = "/z-first/*" },
      { path_pattern = "/static/*" },
      { path_pattern = "/static/images/*" },
      { path_pattern = "/a-last/*" },
    ]
  }

  assert {
    condition     = [for behavior in aws_cloudfront_distribution.this.ordered_cache_behavior : behavior.path_pattern] == ["/z-first/*", "/static/*", "/static/images/*", "/a-last/*"]
    error_message = "ordered_cache_behavior must render exactly in cache_behaviors list order, never re-sorted by path_pattern."
  }
}

run "honours_a_caller_supplied_cache_policy_id" {
  command = plan

  variables {
    cache_behaviors = [
      {
        path_pattern    = "/api/*"
        cache_policy_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
        compress        = false
      },
    ]
  }

  assert {
    condition     = aws_cloudfront_distribution.this.ordered_cache_behavior[0].cache_policy_id == "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    error_message = "A caller-supplied cache_policy_id must not be replaced by the managed default."
  }

  assert {
    condition     = aws_cloudfront_distribution.this.ordered_cache_behavior[0].compress == false
    error_message = "compress = false must be honoured."
  }
}

run "rejects_a_wildcard_path_pattern" {
  command = plan

  variables {
    cache_behaviors = [{ path_pattern = "*" }]
  }

  expect_failures = [var.cache_behaviors]
}

run "rejects_an_empty_path_pattern" {
  command = plan

  variables {
    cache_behaviors = [{ path_pattern = "" }]
  }

  expect_failures = [var.cache_behaviors]
}

run "rejects_a_duplicate_path_pattern" {
  # A map made duplicates impossible; a list must reject them explicitly, as
  # the second entry could never match.
  command = plan

  variables {
    cache_behaviors = [
      { path_pattern = "/static/*" },
      { path_pattern = "/static/*", compress = false },
    ]
  }

  expect_failures = [var.cache_behaviors]
}
