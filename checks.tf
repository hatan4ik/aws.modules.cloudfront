# Advisory checks: they warn on every plan and apply but never block. Each
# describes a configuration that is valid yet usually unintended given ADR
# 0004's edge architecture.

check "access_logging_disabled" {
  assert {
    condition     = var.logging != null
    error_message = "Standard CloudFront access logging is disabled (logging is null). Turn it on with a caller-owned S3 bucket unless the distribution genuinely needs no access log."
  }
}

check "web_acl_not_attached" {
  assert {
    condition     = var.web_acl_arn != null
    error_message = "No WAF Web ACL is attached (web_acl_arn is null). ADR 0004 places a global WAF at every entry layer; attach a CLOUDFRONT-scope Web ACL from aws.modules.waf unless this distribution is deliberately unprotected."
  }
}
