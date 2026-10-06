# Changelog

All notable changes to this module are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Consumers pin the commit SHA of a release tag; see [Versioning and releases](README.md#versioning-and-releases).

## [Unreleased]

Targets **v2.0.0**. Contains breaking interface changes; read [docs/UPGRADE-2.0.md](docs/UPGRADE-2.0.md) before upgrading.

### Changed (BREAKING)

- **`cache_behaviors` is now an ordered `list(object({ path_pattern = string, ... }))`, not a `map` keyed by `path_pattern`.** CloudFront uses the *first* ordered cache behavior whose pattern matches, and a `dynamic` block over a map iterates in lexical key order, so in v1.0.0 precedence was decided by string sort, not by the caller: `"/static/*"` always rendered before `"/static/images/*"` and the narrower pattern could never match. The list order is now exactly the order CloudFront evaluates. Move each map key into a `path_pattern` field and order entries most specific first. New validations: `path_pattern` must be non-empty and unique (`"*"` is still rejected). See [docs/UPGRADE-2.0.md](docs/UPGRADE-2.0.md#1-cache_behaviors-is-now-an-ordered-list-not-a-map).
- `minimum_protocol_version` no longer accepts `TLSv1`, `TLSv1_2016`, or `TLSv1.1_2016`, which allow deprecated TLS 1.0/1.1. The default (`TLSv1.2_2021`) is unchanged.
- `partition` accepts only `aws`, and a looked-up partition other than `aws` fails a resource precondition. v1.0.0 accepted `aws-cn` but always returned the standard partition's `hosted_zone_id` (`Z2FDTNDATAQYW2`; China's is `Z3RFFRIM2A3IF5`), and the module cannot work there anyway: CloudFront in the China Regions supports neither Origin Access Control, ACM viewer certificates, nor AWS WAF, and AWS GovCloud (US) has no CloudFront.

### Fixed

- The README's `aws.modules.s3` composition example hand-translated the bucket statement but omitted `resources`, which `aws.modules.s3` defaults to the whole bucket and its objects: the grant ignored `origin_path` and also covered the bucket ARN itself. The example now merges `required_bucket_policy_statement`, which always sets `resources` to the origin-path-scoped object ARN.
- **`web_acl_arn` rejected every real CLOUDFRONT-scope WAFv2 Web ACL ARN.** The validation required the literal string `global` in the ARN's *region* segment, but AWS issues `arn:aws:wafv2:us-east-1:<account>:global/webacl/<name>/<id>`: the region is `us-east-1` and `global` appears only in the resource segment. `aws.modules.waf`'s real output could therefore never be attached, making ADR 0004's WAF-on-CloudFront composition impossible. The validation now checks the `us-east-1` region segment and the `global/webacl/` resource segment. Not breaking: the previously required shape is one AWS never issues.
- `web_acl_arn`'s Web ACL name segment now accepts underscores (`[a-zA-Z0-9_-]{1,128}`), matching what `aws.modules.waf` and the WAFv2 API allow, and the same character class as `aws.modules.alb`'s REGIONAL-scope validation.
- Every test and example used a fabricated `arn:aws:wafv2:global:...` ARN that happened to satisfy the wrong regex; all now use real-shaped ARNs, and new tests prove a real ARN and an underscore name are accepted and the fabricated shape is rejected.
- `docs/DESIGN.md` claimed a CLOUDFRONT-scope ARN carries `global` in its region segment and that its `us-east-1` origin could not be validated; corrected.

### Added

- `required_bucket_policy_statement` and `required_kms_key_policy_statement` outputs: the same two grants as `required_bucket_policy_json` and `required_kms_key_policy_json`, as Sid-keyed objects in exactly the shape of `aws.modules.s3`'s `bucket_policy_statements` and `aws.modules.kms`'s `policy_statements` inputs, so composing the fleet needs no `jsondecode`-and-rebuild translation (`bucket_policy_statements = merge(module.distribution.required_bucket_policy_statement, { ... })`). Derived mechanically from the same locals as the JSON outputs, so the two shapes cannot drift. Additive and non-breaking: the JSON outputs are unchanged and stay the shape for callers outside the module fleet. See `docs/DESIGN.md`, "Typed statement outputs for aws.modules.s3 and aws.modules.kms".
- `tests/policy_statement_bridge.tftest.hcl` and the `tests/fixtures/sibling-statement-types` fixture: both typed outputs, merged with another statement, convert to literal copies of the sibling input types, and every field equals the decoded JSON statement.
- `required_kms_key_policy_json` output: the KMS key-policy statement (`kms:Decrypt` for `cloudfront.amazonaws.com`, scoped by `AWS:SourceArn` to this distribution) an origin bucket's customer managed key needs when objects use SSE-KMS. The README documents that the AWS managed `aws/s3` key (`aws.modules.s3`'s default) cannot be used with OAC at all, since its key policy is not editable, and that a missing statement fails closed with 403.
- `minimum_protocol_version` accepts the current CloudFront security policies `TLSv1.2_2025` and `TLSv1.3_2025`.
- Contract tests proving list order is CloudFront precedence order (a narrower pattern listed first renders first; order is never re-sorted), for the TLS and partition validations, and for the KMS statement.
- The integration smoke suite now proves the OAC read path end to end: through a new `tests/integration/probe` module it fetches a known fixture object through the real distribution, expecting `403` with no bucket policy and `200` with the exact body once `required_bucket_policy_json` is attached as the bucket's only grant.
- README and `docs/DESIGN.md` document CloudFront's default 25 cache behaviors and 100 aliases per distribution quotas.

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
