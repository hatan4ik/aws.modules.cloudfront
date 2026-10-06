# required_bucket_policy_statement and required_kms_key_policy_statement: the
# same grants as the two *_json outputs, shaped for aws.modules.s3's
# bucket_policy_statements and aws.modules.kms's policy_statements inputs.
#
# Two properties are proved here:
#
# 1. Type compatibility. tests/fixtures/sibling-statement-types declares
#    literal copies of both sibling input types; the fixture runs assign the
#    outputs to them (merged with an unrelated caller statement, the
#    documented usage), so a shape the siblings would reject fails this file.
# 2. Semantic equality. Every field of the converted typed statement is
#    asserted against the jsondecode()d JSON output, so the two shapes are
#    provably the same grant. Structured fields are compared through
#    jsonencode(), which renders a converted map(set(string)) and an object
#    literal identically (attributes in key order, sets as sorted lists),
#    since == on HCL values also compares their types.
#
# Like tests/bucket_policy.tftest.hcl this needs command = apply (both
# statements embed the distribution ARN, unknown at plan time for a fresh
# create) and therefore lives in its own file, away from every plan-only run.

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
    origin_path                 = "/site"
  }
  web_acl_arn = "arn:aws:wafv2:us-east-1:123456789012:global/webacl/static-site/11111111-1111-1111-1111-111111111111"
  logging = {
    bucket_domain_name = "static-site-logs.s3.amazonaws.com"
  }
}

run "bridge" {
  command = apply

  assert {
    condition     = keys(output.required_bucket_policy_statement) == [jsondecode(output.required_bucket_policy_json).Sid]
    error_message = "required_bucket_policy_statement must hold exactly one entry, keyed by the JSON statement's Sid."
  }

  assert {
    condition     = keys(output.required_kms_key_policy_statement) == [jsondecode(output.required_kms_key_policy_json).Sid]
    error_message = "required_kms_key_policy_statement must hold exactly one entry, keyed by the JSON statement's Sid."
  }
}

run "bucket_statement_converts_to_aws_modules_s3_bucket_policy_statements" {
  command = apply

  module {
    source = "./tests/fixtures/sibling-statement-types"
  }

  variables {
    s3_bucket_policy_statements = merge(run.bridge.required_bucket_policy_statement, {
      AllowAuditListBucket = {
        principals = { AWS = ["arn:aws:iam::123456789012:role/audit"] }
        actions    = ["s3:ListBucket"]
      }
    })
  }

  assert {
    condition     = toset(keys(output.s3_bucket_policy_statements)) == toset(["AllowCloudFrontServicePrincipalReadOnly", "AllowAuditListBucket"])
    error_message = "Merging the output with another statement must keep both entries under their own Sids."
  }

  assert {
    condition     = output.s3_bucket_policy_statements["AllowCloudFrontServicePrincipalReadOnly"].effect == jsondecode(run.bridge.required_bucket_policy_json).Effect
    error_message = "effect must equal the JSON statement's Effect."
  }

  assert {
    condition     = jsonencode(output.s3_bucket_policy_statements["AllowCloudFrontServicePrincipalReadOnly"].principals) == jsonencode({ Service = [jsondecode(run.bridge.required_bucket_policy_json).Principal.Service] }) && output.s3_bucket_policy_statements["AllowCloudFrontServicePrincipalReadOnly"].principal_all == false
    error_message = "principals must be exactly { Service = [cloudfront.amazonaws.com] } (the JSON Principal) and principal_all must stay false."
  }

  assert {
    condition     = output.s3_bucket_policy_statements["AllowCloudFrontServicePrincipalReadOnly"].actions == toset([jsondecode(run.bridge.required_bucket_policy_json).Action]) && output.s3_bucket_policy_statements["AllowCloudFrontServicePrincipalReadOnly"].actions == toset(["s3:GetObject"])
    error_message = "actions must be exactly the JSON statement's Action, s3:GetObject."
  }

  assert {
    condition     = output.s3_bucket_policy_statements["AllowCloudFrontServicePrincipalReadOnly"].resources == toset([jsondecode(run.bridge.required_bucket_policy_json).Resource]) && output.s3_bucket_policy_statements["AllowCloudFrontServicePrincipalReadOnly"].resources == toset(["arn:aws:s3:::static-site-origin/site/*"])
    error_message = "resources must be exactly the JSON statement's Resource, scoped to the origin_path prefix (null would widen it to the whole bucket in aws.modules.s3)."
  }

  assert {
    condition = jsonencode(output.s3_bucket_policy_statements["AllowCloudFrontServicePrincipalReadOnly"].conditions) == jsonencode([{
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [jsondecode(run.bridge.required_bucket_policy_json).Condition.StringEquals["AWS:SourceArn"]]
    }])
    error_message = "conditions must be exactly the JSON statement's one StringEquals AWS:SourceArn condition."
  }

  assert {
    condition     = one(one(output.s3_bucket_policy_statements["AllowCloudFrontServicePrincipalReadOnly"].conditions).values) == "arn:aws:cloudfront::123456789012:distribution/E1234567890ABC"
    error_message = "The AWS:SourceArn condition must carry this distribution's own ARN; without it any distribution in the account could read the bucket."
  }
}

run "kms_statement_converts_to_aws_modules_kms_policy_statements" {
  command = apply

  module {
    source = "./tests/fixtures/sibling-statement-types"
  }

  variables {
    kms_policy_statements = merge(run.bridge.required_kms_key_policy_statement, {
      AllowAuditDescribeKey = {
        principals = { AWS = ["arn:aws:iam::123456789012:role/audit"] }
        actions    = ["kms:DescribeKey"]
      }
    })
  }

  assert {
    condition     = toset(keys(output.kms_policy_statements)) == toset(["AllowCloudFrontServicePrincipalSSEKMSDecrypt", "AllowAuditDescribeKey"])
    error_message = "Merging the output with another statement must keep both entries under their own Sids."
  }

  assert {
    condition     = output.kms_policy_statements["AllowCloudFrontServicePrincipalSSEKMSDecrypt"].effect == jsondecode(run.bridge.required_kms_key_policy_json).Effect
    error_message = "effect must equal the JSON statement's Effect."
  }

  assert {
    condition     = jsonencode(output.kms_policy_statements["AllowCloudFrontServicePrincipalSSEKMSDecrypt"].principals) == jsonencode({ Service = [jsondecode(run.bridge.required_kms_key_policy_json).Principal.Service] })
    error_message = "principals must be exactly { Service = [cloudfront.amazonaws.com] } (the JSON Principal)."
  }

  assert {
    condition     = output.kms_policy_statements["AllowCloudFrontServicePrincipalSSEKMSDecrypt"].actions == toset([jsondecode(run.bridge.required_kms_key_policy_json).Action]) && output.kms_policy_statements["AllowCloudFrontServicePrincipalSSEKMSDecrypt"].actions == toset(["kms:Decrypt"])
    error_message = "actions must be exactly the JSON statement's Action, kms:Decrypt."
  }

  assert {
    condition     = output.kms_policy_statements["AllowCloudFrontServicePrincipalSSEKMSDecrypt"].resources == toset([jsondecode(run.bridge.required_kms_key_policy_json).Resource]) && output.kms_policy_statements["AllowCloudFrontServicePrincipalSSEKMSDecrypt"].resources == toset(["*"])
    error_message = "resources must be exactly the JSON statement's Resource, \"*\" (the key the policy is attached to)."
  }

  assert {
    condition = jsonencode(output.kms_policy_statements["AllowCloudFrontServicePrincipalSSEKMSDecrypt"].conditions) == jsonencode([{
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = ["arn:aws:cloudfront::123456789012:distribution/E1234567890ABC"]
    }]) && jsondecode(run.bridge.required_kms_key_policy_json).Condition.StringEquals["AWS:SourceArn"] == "arn:aws:cloudfront::123456789012:distribution/E1234567890ABC"
    error_message = "conditions must be exactly the JSON statement's one StringEquals AWS:SourceArn condition on this distribution's own ARN."
  }
}
