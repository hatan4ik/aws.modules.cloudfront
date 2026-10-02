provider "aws" {
  region = var.region
}

module "distribution" {
  source = "../../"

  name = var.name

  origin = {
    bucket_name                 = var.bucket_name
    bucket_regional_domain_name = var.bucket_regional_domain_name
  }

  # A single-page application's client-side router owns every path, so a
  # request for a route the app defines (which does not exist as an S3 key)
  # returns the origin's 403 (private bucket, no such key) or 404. Rewriting
  # both to /index.html with a 200 hands the route back to the app.
  custom_error_responses = [
    {
      error_code         = 403
      response_code      = 200
      response_page_path = "/index.html"
    },
    {
      error_code         = 404
      response_code      = 200
      response_page_path = "/index.html"
    },
  ]

  # Cache the app shell briefly so a new deployment is visible without
  # waiting out a long default TTL, while static, hashed assets under
  # /static/* still use the long-lived managed policy.
  default_cache_behavior = {
    cache_policy_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # AWS managed CachingDisabled
  }

  # A list: CloudFront uses the first matching behavior, in this order. A
  # narrower pattern (say "/static/images/*") must be listed before
  # "/static/*" to ever match.
  cache_behaviors = [
    { path_pattern = "/static/*" },
  ]
}
