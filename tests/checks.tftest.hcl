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

run "passes_both_advisory_checks_when_logging_and_waf_are_set" {
  command = plan
}

run "warns_when_logging_is_null" {
  command = plan
  variables { logging = null }
  expect_failures = [check.access_logging_disabled]
}

run "warns_when_web_acl_arn_is_null" {
  command = plan
  variables { web_acl_arn = null }
  expect_failures = [check.web_acl_not_attached]
}

run "warns_on_both_checks_with_no_logging_and_no_waf" {
  command = plan
  variables {
    logging     = null
    web_acl_arn = null
  }
  expect_failures = [check.access_logging_disabled, check.web_acl_not_attached]
}
