# Integration suite: real apply in the caller's own account.
#
# Requires AWS credentials and a region from the environment (for example
# AWS_PROFILE and AWS_REGION, or the OIDC role assumed by the integration
# workflow). Nothing is hard-coded: tests/integration/setup creates a
# disposable, private S3 bucket with a random suffix (plainly, not through
# aws.modules.s3, per the module's brief - see its own file header), the
# module under test is applied against that bucket with otherwise every
# default, the results are asserted against the real CloudFront and S3 APIs,
# and everything is destroyed at the end of the file.
#
# aws_cloudfront_distribution waits for the distribution to reach the
# Deployed state on both create and destroy by default (wait_for_deployment),
# so this suite commonly takes 15-25 minutes each way. That is expected of a
# real CloudFront apply/destroy, not a hang; see tests/integration/README.md.
#
# Run: terraform init -backend=false -test-directory=tests/integration
#      terraform test -test-directory=tests/integration -filter=tests/integration/smoke.tftest.hcl

provider "aws" {}

run "setup" {
  module {
    source = "./tests/integration/setup"
  }

  variables {
    name_prefix = "cloudfront-it"
  }
}

run "smoke" {
  variables {
    name = "cloudfront-integration-smoke"

    origin = {
      bucket_name                 = run.setup.bucket_name
      bucket_regional_domain_name = run.setup.bucket_regional_domain_name
    }

    tags = run.setup.tags
  }

  assert {
    condition     = output.distribution_id != "" && startswith(output.distribution_arn, "arn:aws:cloudfront::")
    error_message = "The distribution must exist under a real CloudFront ARN."
  }

  assert {
    condition     = endswith(output.domain_name, ".cloudfront.net")
    error_message = "With no aliases the distribution must be reachable at its own *.cloudfront.net domain."
  }

  assert {
    condition     = output.hosted_zone_id == "Z2FDTNDATAQYW2"
    error_message = "hosted_zone_id must still be CloudFront's fixed alias-target zone ID against the real API, exactly as asserted under mock_provider in tests/defaults.tftest.hcl."
  }

  assert {
    condition     = output.origin_access_control_id != ""
    error_message = "The Origin Access Control must have been created."
  }

  assert {
    condition     = jsondecode(output.required_bucket_policy_json).Condition.StringEquals["AWS:SourceArn"] == output.distribution_arn
    error_message = "required_bucket_policy_json's AWS:SourceArn must equal this real distribution's own ARN, exactly as proven under mock_provider in tests/bucket_policy.tftest.hcl - this is the suite's most important assertion, since a wrong SourceArn here would let any CloudFront distribution in the account read the bucket."
  }

  assert {
    condition     = jsondecode(output.required_bucket_policy_json).Resource == "${run.setup.bucket_arn}/*"
    error_message = "required_bucket_policy_json's Resource must cover every object in the real fixture bucket."
  }
}
