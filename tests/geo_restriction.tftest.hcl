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

run "defaults_to_no_restriction" {
  command = plan

  assert {
    condition     = aws_cloudfront_distribution.this.restrictions[0].geo_restriction[0].restriction_type == "none" && length(aws_cloudfront_distribution.this.restrictions[0].geo_restriction[0].locations) == 0
    error_message = "geo_restriction must default to none with no locations."
  }
}

run "renders_a_whitelist" {
  command = plan

  variables {
    geo_restriction = {
      restriction_type = "whitelist"
      locations        = ["US", "CA", "DE"]
    }
  }

  assert {
    condition     = aws_cloudfront_distribution.this.restrictions[0].geo_restriction[0].restriction_type == "whitelist" && toset(aws_cloudfront_distribution.this.restrictions[0].geo_restriction[0].locations) == toset(["US", "CA", "DE"])
    error_message = "A whitelist must render its restriction_type and locations exactly."
  }
}

run "renders_a_blacklist" {
  command = plan

  variables {
    geo_restriction = {
      restriction_type = "blacklist"
      locations        = ["KP"]
    }
  }

  assert {
    condition     = aws_cloudfront_distribution.this.restrictions[0].geo_restriction[0].restriction_type == "blacklist" && toset(aws_cloudfront_distribution.this.restrictions[0].geo_restriction[0].locations) == toset(["KP"])
    error_message = "A blacklist must render its restriction_type and locations exactly."
  }
}

run "rejects_whitelist_with_no_locations" {
  command = plan

  variables {
    geo_restriction = { restriction_type = "whitelist" }
  }

  expect_failures = [var.geo_restriction]
}

run "rejects_blacklist_with_no_locations" {
  command = plan

  variables {
    geo_restriction = { restriction_type = "blacklist", locations = [] }
  }

  expect_failures = [var.geo_restriction]
}

run "rejects_an_unknown_restriction_type" {
  command = plan

  variables {
    geo_restriction = { restriction_type = "allow" }
  }

  expect_failures = [var.geo_restriction]
}

run "rejects_a_lowercase_country_code" {
  command = plan

  variables {
    geo_restriction = { restriction_type = "whitelist", locations = ["us"] }
  }

  expect_failures = [var.geo_restriction]
}
