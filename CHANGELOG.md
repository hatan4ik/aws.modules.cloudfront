# Changelog

All notable changes to this module are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Consumers pin the commit SHA of a release tag; see [Versioning and releases](README.md#versioning-and-releases).

## [Unreleased]

## [1.0.0] - 2026-09-27

Initial release. Brand new module: no prior 0.x line, no live consumer, no `docs/UPGRADE-1.0.md`.

### Added

- One `aws_cloudfront_origin_access_control` (OAC, not the legacy Origin Access Identity) and one `aws_cloudfront_distribution` per module call, serving one private S3 origin, per [ADR 0004](/docs/adr/0004-edge-ingress-and-egress.md)'s static delivery path.
- `origin` (`bucket_name`, `bucket_regional_domain_name`, optional `origin_path`) identifying a caller-owned bucket this module never creates or reaches into.
- `required_bucket_policy_json`: the exact IAM policy statement the origin bucket needs, scoped by `Condition.StringEquals["AWS:SourceArn"]` to this distribution's own ARN, for the caller to merge into the bucket's own policy.
- `price_class` (default `PriceClass_100`), `default_root_object` (default `index.html`), `aliases`, `viewer_certificate_arn` (validated as a `us-east-1` ACM ARN when set), `minimum_protocol_version` (default `TLSv1.2_2021`), `web_acl_arn` (validated as a CLOUDFRONT-scope WAFv2 ARN when set).
- `default_cache_behavior` and `cache_behaviors` (map keyed by `path_pattern`, `"*"` rejected as a key), both defaulting `cache_policy_id` to the AWS managed `CachingOptimized` policy when unset.
- `geo_restriction` (`none`/`whitelist`/`blacklist`, with `locations` required and validated as uppercase ISO 3166-1 alpha-2 codes for the latter two).
- `logging` (optional, off by default) and `custom_error_responses` (SPA-style rewrites).
- Outputs `distribution_id`, `distribution_arn`, `domain_name`, `hosted_zone_id` (CloudFront's fixed alias-target zone ID), `origin_access_control_id`, `required_bucket_policy_json`.
- Advisory `check` blocks `access_logging_disabled` and `web_acl_not_attached`.
- Plan-time validation of `name`, `origin`, `price_class`, `default_root_object`, `aliases`, the alias/certificate mutual requirement (as resource preconditions), the ACM ARN's `us-east-1` region segment, `minimum_protocol_version`, the WAFv2 Web ACL ARN's CLOUDFRONT-scope shape, `geo_restriction`, and `custom_error_responses`.
- 48 mock-provider contract tests in `tests/`, including a dedicated `bucket_policy.tftest.hcl` using `command = apply` with an explicit `mock_resource` ARN override to prove the `AWS:SourceArn` condition on a value only known after apply.
- Examples `minimal`, `custom-domain-with-waf`, and `spa-with-error-rewrites`.
- Credential-driven integration suite `smoke` in `tests/integration/` (a disposable, plain S3 bucket fixture and a minimal distribution against it, destroyed after — CloudFront distributions are slow both to create and delete in real AWS), a `make integration-smoke` target, a dispatch-only `integration` workflow that assumes a role through GitHub OIDC from the protected `integration` environment, and the IAM trust and permissions documents the role needs.
- `docs/DESIGN.md`, `CONTRIBUTING.md`, `SECURITY.md`, `LICENSE`, the `Makefile` quality gate, pre-commit, tflint, checkov, trivy, and terraform-docs configuration, Dependabot, issue and pull request templates, and the `terraform-quality` and `module-release` workflows.

[Unreleased]: https://github.com/hatan4ik/aws.modules.cloudfront/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/hatan4ik/aws.modules.cloudfront/releases/tag/v1.0.0
