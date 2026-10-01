# required_bucket_policy_json is only known after apply on a fresh create: it
# is rendered from aws_cloudfront_distribution.this.arn, which is unknown at
# plan time for a resource that does not yet exist. This file therefore uses
# command = apply under mock_provider with an explicit mock_resource override
# for the distribution's ARN, the same way this session's aws.modules.ecs
# root tests handled a computed-ARN assertion, and stays isolated from every
# plan-only run elsewhere in tests/ per the "apply runs need their own file"
# rule: run blocks in one .tftest.hcl file share state, and an apply run
# leaking into a later plan run in the same file would make a computed value
# unexpectedly known.
#
# This is the module's most important correctness property: a wrong or
# missing AWS:SourceArn condition would let ANY CloudFront distribution in
# the account read the origin bucket, not just this one.

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }

  mock_resource "aws_cloudfront_distribution" {
    defaults = {
      arn = "arn:aws:cloudfront::123456789012:distribution/E1234567890ABC"
    }
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

run "scopes_the_bucket_policy_statement_to_this_distributions_own_arn" {
  command = apply

  assert {
    condition     = aws_cloudfront_distribution.this.arn == "arn:aws:cloudfront::123456789012:distribution/E1234567890ABC"
    error_message = "The mocked distribution must produce the overridden ARN."
  }

  assert {
    condition     = jsondecode(output.required_bucket_policy_json).Condition.StringEquals["AWS:SourceArn"] == aws_cloudfront_distribution.this.arn
    error_message = "required_bucket_policy_json's AWS:SourceArn condition must equal this distribution's own ARN. A wrong or missing SourceArn condition would let any CloudFront distribution in the account read the bucket, not just this one."
  }

  assert {
    condition     = jsondecode(output.required_bucket_policy_json).Effect == "Allow" && jsondecode(output.required_bucket_policy_json).Principal.Service == "cloudfront.amazonaws.com" && jsondecode(output.required_bucket_policy_json).Action == "s3:GetObject"
    error_message = "The statement must grant only s3:GetObject to the cloudfront.amazonaws.com service principal."
  }

  assert {
    condition     = jsondecode(output.required_bucket_policy_json).Resource == "arn:aws:s3:::static-site-origin/*"
    error_message = "With no origin_path the statement's Resource must cover every object in the bucket."
  }

  assert {
    condition     = jsondecode(output.required_bucket_policy_json).Sid == "AllowCloudFrontServicePrincipalReadOnly"
    error_message = "The statement must carry a stable, descriptive Sid so a caller can find it after merging."
  }
}

run "scopes_the_bucket_policy_resource_to_the_origin_path_when_set" {
  command = apply

  variables {
    origin = {
      bucket_name                 = "static-site-origin"
      bucket_regional_domain_name = "static-site-origin.s3.us-east-1.amazonaws.com"
      origin_path                 = "/site"
    }
  }

  assert {
    condition     = jsondecode(output.required_bucket_policy_json).Resource == "arn:aws:s3:::static-site-origin/site/*"
    error_message = "origin_path must scope the bucket policy Resource to that prefix, not just the bucket root."
  }

  assert {
    condition     = jsondecode(output.required_bucket_policy_json).Condition.StringEquals["AWS:SourceArn"] == aws_cloudfront_distribution.this.arn
    error_message = "The SourceArn condition must still equal this distribution's own ARN when an origin_path is set."
  }
}

run "honours_a_caller_supplied_partition" {
  command = apply

  variables {
    partition = "aws-us-gov"
  }

  assert {
    condition     = jsondecode(output.required_bucket_policy_json).Resource == "arn:aws-us-gov:s3:::static-site-origin/*"
    error_message = "A caller-supplied partition must render in the statement's Resource ARN instead of the looked-up one."
  }
}
