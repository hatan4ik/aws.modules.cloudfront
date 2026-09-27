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
}

run "renders_no_custom_error_responses_by_default" {
  command = plan

  assert {
    condition     = length(aws_cloudfront_distribution.this.custom_error_response) == 0
    error_message = "No custom_error_response block may render unless declared."
  }
}

run "renders_spa_style_rewrites_for_403_and_404" {
  command = plan

  variables {
    custom_error_responses = [
      { error_code = 403, response_code = 200, response_page_path = "/index.html" },
      { error_code = 404, response_code = 200, response_page_path = "/index.html", error_caching_min_ttl = 10 },
    ]
  }

  assert {
    condition     = length(aws_cloudfront_distribution.this.custom_error_response) == 2
    error_message = "One custom_error_response must render per declared entry."
  }

  assert {
    condition     = alltrue([for response in aws_cloudfront_distribution.this.custom_error_response : response.response_code == 200 && response.response_page_path == "/index.html"])
    error_message = "Every declared rewrite must render its response_code and response_page_path."
  }

  assert {
    condition     = [for response in aws_cloudfront_distribution.this.custom_error_response : response.error_caching_min_ttl if response.error_code == 404][0] == 10
    error_message = "A declared error_caching_min_ttl must override the 300 second default."
  }

  assert {
    condition     = [for response in aws_cloudfront_distribution.this.custom_error_response : response.error_caching_min_ttl if response.error_code == 403][0] == 300
    error_message = "error_caching_min_ttl must default to 300 seconds."
  }
}

run "rejects_an_error_code_cloudfront_does_not_support" {
  command = plan

  variables {
    custom_error_responses = [{ error_code = 418 }]
  }

  expect_failures = [var.custom_error_responses]
}

run "rejects_a_response_code_without_a_response_page_path" {
  command = plan

  variables {
    custom_error_responses = [{ error_code = 404, response_code = 200 }]
  }

  expect_failures = [var.custom_error_responses]
}

run "rejects_a_negative_error_caching_min_ttl" {
  command = plan

  variables {
    custom_error_responses = [{ error_code = 404, error_caching_min_ttl = -1 }]
  }

  expect_failures = [var.custom_error_responses]
}
