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

# ---------------------------------------------------------------------------
# name
# ---------------------------------------------------------------------------

run "rejects_an_empty_name" {
  command = plan
  variables { name = "" }
  expect_failures = [var.name]
}

run "rejects_a_name_over_64_characters" {
  command = plan
  variables { name = join("", [for i in range(65) : "a"]) }
  expect_failures = [var.name]
}

run "rejects_a_name_with_disallowed_characters" {
  command = plan
  variables { name = "static/site" }
  expect_failures = [var.name]
}

# ---------------------------------------------------------------------------
# origin
# ---------------------------------------------------------------------------

run "rejects_an_empty_bucket_name" {
  command = plan
  variables {
    origin = { bucket_name = "", bucket_regional_domain_name = "b.s3.us-east-1.amazonaws.com" }
  }
  expect_failures = [var.origin]
}

run "rejects_an_empty_bucket_regional_domain_name" {
  command = plan
  variables {
    origin = { bucket_name = "b", bucket_regional_domain_name = "" }
  }
  expect_failures = [var.origin]
}

run "rejects_an_origin_path_without_a_leading_slash" {
  command = plan
  variables {
    origin = { bucket_name = "b", bucket_regional_domain_name = "b.s3.us-east-1.amazonaws.com", origin_path = "site" }
  }
  expect_failures = [var.origin]
}

run "rejects_an_origin_path_with_a_trailing_slash" {
  command = plan
  variables {
    origin = { bucket_name = "b", bucket_regional_domain_name = "b.s3.us-east-1.amazonaws.com", origin_path = "/site/" }
  }
  expect_failures = [var.origin]
}

run "accepts_a_well_formed_origin_path" {
  command = plan
  variables {
    origin = { bucket_name = "b", bucket_regional_domain_name = "b.s3.us-east-1.amazonaws.com", origin_path = "/site" }
  }
}

# ---------------------------------------------------------------------------
# price_class / default_root_object
# ---------------------------------------------------------------------------

run "rejects_an_unknown_price_class" {
  command = plan
  variables { price_class = "PriceClass_Cheap" }
  expect_failures = [var.price_class]
}

run "rejects_a_default_root_object_with_a_leading_slash" {
  command = plan
  variables { default_root_object = "/index.html" }
  expect_failures = [var.default_root_object]
}

# ---------------------------------------------------------------------------
# aliases
# ---------------------------------------------------------------------------

run "rejects_a_malformed_alias" {
  command = plan
  variables { aliases = ["not a domain"] }
  expect_failures = [var.aliases]
}

run "rejects_an_uppercase_alias" {
  command = plan
  variables { aliases = ["App.example.com"] }
  expect_failures = [var.aliases]
}

# ---------------------------------------------------------------------------
# viewer_certificate_arn: shape and the us-east-1 constraint
# ---------------------------------------------------------------------------

run "rejects_a_certificate_arn_outside_us_east_1" {
  command = plan
  variables {
    aliases                = ["app.example.com"]
    viewer_certificate_arn = "arn:aws:acm:eu-west-1:123456789012:certificate/11111111-2222-3333-4444-555555555555"
  }
  expect_failures = [var.viewer_certificate_arn]
}

run "rejects_a_non_acm_certificate_arn" {
  command = plan
  variables {
    aliases                = ["app.example.com"]
    viewer_certificate_arn = "arn:aws:iam::123456789012:server-certificate/example"
  }
  expect_failures = [var.viewer_certificate_arn]
}

run "accepts_a_well_formed_us_east_1_certificate_arn" {
  command = plan
  variables {
    aliases                = ["app.example.com"]
    viewer_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/11111111-2222-3333-4444-555555555555"
  }
}

# ---------------------------------------------------------------------------
# minimum_protocol_version
# ---------------------------------------------------------------------------

run "rejects_an_unknown_minimum_protocol_version" {
  command = plan
  variables { minimum_protocol_version = "TLSv1.3" }
  expect_failures = [var.minimum_protocol_version]
}

# ---------------------------------------------------------------------------
# web_acl_arn
# ---------------------------------------------------------------------------

run "rejects_a_regional_scope_web_acl_arn" {
  command = plan
  variables {
    web_acl_arn = "arn:aws:wafv2:us-east-1:123456789012:regional/webacl/example/11111111-1111-1111-1111-111111111111"
  }
  expect_failures = [var.web_acl_arn]
}

run "rejects_a_malformed_web_acl_arn" {
  command = plan
  variables {
    web_acl_arn = "arn:aws:wafv2:global:123456789012:global/webacl/example"
  }
  expect_failures = [var.web_acl_arn]
}

run "accepts_a_well_formed_cloudfront_scope_web_acl_arn" {
  command = plan
  variables {
    web_acl_arn = "arn:aws:wafv2:global:123456789012:global/webacl/example/11111111-1111-1111-1111-111111111111"
  }
}
