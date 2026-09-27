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

run "uses_the_default_certificate_with_no_aliases" {
  command = plan

  assert {
    condition     = length(aws_cloudfront_distribution.this.aliases) == 0
    error_message = "This run's baseline must declare no aliases."
  }

  assert {
    condition     = aws_cloudfront_distribution.this.viewer_certificate[0].cloudfront_default_certificate == true
    error_message = "cloudfront_default_certificate must be true with no aliases."
  }

  assert {
    condition     = aws_cloudfront_distribution.this.viewer_certificate[0].acm_certificate_arn == null && aws_cloudfront_distribution.this.viewer_certificate[0].ssl_support_method == null
    error_message = "No ACM certificate or SSL support method may render with the default certificate."
  }
}

run "uses_the_acm_certificate_with_sni_when_aliases_are_set" {
  command = plan

  variables {
    aliases                  = ["app.example.com", "*.app.example.com"]
    viewer_certificate_arn   = "arn:aws:acm:us-east-1:123456789012:certificate/11111111-2222-3333-4444-555555555555"
    minimum_protocol_version = "TLSv1.2_2019"
  }

  assert {
    condition     = toset(aws_cloudfront_distribution.this.aliases) == toset(["app.example.com", "*.app.example.com"])
    error_message = "aliases must render exactly as declared."
  }

  assert {
    condition     = aws_cloudfront_distribution.this.viewer_certificate[0].acm_certificate_arn == "arn:aws:acm:us-east-1:123456789012:certificate/11111111-2222-3333-4444-555555555555"
    error_message = "The declared certificate ARN must be attached."
  }

  assert {
    condition     = aws_cloudfront_distribution.this.viewer_certificate[0].ssl_support_method == "sni-only" && aws_cloudfront_distribution.this.viewer_certificate[0].minimum_protocol_version == "TLSv1.2_2019"
    error_message = "A custom domain must use SNI and the declared minimum protocol version."
  }

  assert {
    condition     = aws_cloudfront_distribution.this.viewer_certificate[0].cloudfront_default_certificate != true
    error_message = "The default certificate must not be used once a custom domain certificate is attached."
  }
}

run "rejects_aliases_without_a_certificate" {
  command = plan

  variables {
    aliases = ["app.example.com"]
  }

  expect_failures = [aws_cloudfront_distribution.this]
}

run "rejects_a_certificate_without_aliases" {
  command = plan

  variables {
    viewer_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/11111111-2222-3333-4444-555555555555"
  }

  expect_failures = [aws_cloudfront_distribution.this]
}
