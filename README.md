# aws.modules.cloudfront

Provisions **one** CloudFront distribution per module call, serving **one** private S3 origin through an Origin Access Control (OAC — not the legacy Origin Access Identity). It is the static half of [ADR 0004](/docs/adr/0004-edge-ingress-and-egress.md)'s edge architecture: "CloudFront plus a global WAF delivers static content from private S3 origins." It is deliberately **not** a general-purpose reverse proxy for both static and dynamic content — the dynamic half (Global Accelerator to regional WAF-protected ALBs) is a separate module, `aws.modules.global-accelerator`. It is secure by default, creates nothing beyond the distribution and its OAC, and performs no data-source reads beyond one documented partition fallback. Requires Terraform >= 1.7 and the AWS provider >= 6.35, < 7.

## Why this module

What you get from `name` and `origin`, without setting anything else:

- A private origin, read only through OAC. The bucket stays fully private; CloudFront authenticates to it with SigV4 through the Origin Access Control this module creates. This module cannot attach the bucket's own policy (it does not own the bucket), so it renders the exact statement the bucket needs — `required_bucket_policy_json` — for the caller to merge in. Getting that statement's `AWS:SourceArn` condition right, so only *this* distribution can read the bucket, is the module's most important correctness property; see [Security model](#security-model).
- Secure defaults. `TLSv1.2_2021` minimum protocol version, HTTPS-only viewer traffic (`redirect-to-https`), IPv6 enabled, `PriceClass_100` (the cheapest, US/Canada/Europe edge locations; wider distribution is an explicit opt-in).
- One CloudFront default certificate, or one caller-supplied ACM certificate — never both, never neither. `aliases` empty uses `*.cloudfront.net`; `aliases` non-empty requires `viewer_certificate_arn`, validated to be an ACM ARN in `us-east-1`, the only region CloudFront ever reads viewer certificates from.
- The `CachingOptimized` AWS managed cache policy by default for the default behavior and every additional `cache_behaviors` entry, so static content gets long TTLs and negotiated compression without picking a policy ID.
- SPA-friendly error rewrites and additional path-based cache behaviors as plain data (`custom_error_responses`, `cache_behaviors`), with `"*"` reserved for `default_cache_behavior` and rejected as a `cache_behaviors` `path_pattern`. `cache_behaviors` is an ordered list: its order is CloudFront's match precedence (first match wins).
- Advisory `check` blocks that warn — never block — when access logging or a WAF Web ACL is not attached, since ADR 0004 wants a WAF at every entry layer.
- Plan-time validation of `name`, `origin`, `price_class`, `aliases`, the alias/certificate mutual requirement, the ACM ARN's `us-east-1` region segment, `minimum_protocol_version`, the WAFv2 Web ACL ARN's CLOUDFRONT-scope shape and `us-east-1` region segment, `geo_restriction`, and `custom_error_responses`.
- Only a `Name` tag is added (from `name`); caller tags are never overridden.

## Quick start

```hcl
module "origin_bucket" {
  source = "git::https://github.com/hatan4ik/aws.modules.s3.git?ref=<commit-sha>" # v1.0.0

  bucket = "app-static-site"
  tags   = { Environment = "prod", Owner = "platform" }
}

module "distribution" {
  source = "git::https://github.com/hatan4ik/aws.modules.cloudfront.git?ref=<commit-sha>" # v1.0.0

  name = "app-static-site"

  origin = {
    bucket_name                 = module.origin_bucket.id
    bucket_regional_domain_name = module.origin_bucket.bucket_regional_domain_name
  }

  tags = { Environment = "prod", Owner = "platform" }
}

# This module never reaches into the origin bucket (see docs/DESIGN.md): it
# renders the exact statement the bucket needs and the caller attaches it.
# jsondecode() turns the rendered statement back into an object so it merges
# cleanly with a full policy document; a standalone resource like this works
# regardless of how the bucket itself is managed.
resource "aws_s3_bucket_policy" "origin" {
  bucket = module.origin_bucket.id

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [jsondecode(module.distribution.required_bucket_policy_json)]
  })
}
```

This creates one distribution with every default: `PriceClass_100`, `index.html` as the default root object, the CloudFront default `*.cloudfront.net` certificate (no `aliases` set), the `CachingOptimized` managed cache policy, no WAF, no access logging (both advisory checks warn), and an OAC-only bucket policy scoped to this exact distribution's ARN.

If `aws.modules.s3` already owns this bucket's policy through its own `bucket_policy_statements` input, translate the rendered statement into that input's typed shape instead of merging the raw JSON — the two shapes differ (`aws.modules.s3` takes `principals` as `map(set(string))` and `conditions` as a list of `{ test, variable, values }` objects, not a raw IAM `Principal`/`Condition` block):

```hcl
module "origin_bucket" {
  source = "git::https://github.com/hatan4ik/aws.modules.s3.git?ref=<commit-sha>" # v1.0.0

  bucket = "app-static-site"

  bucket_policy_statements = {
    AllowCloudFrontServicePrincipalReadOnly = {
      principals = { Service = ["cloudfront.amazonaws.com"] }
      actions    = ["s3:GetObject"]
      conditions = [{
        test     = "StringEquals"
        variable = "AWS:SourceArn"
        values   = [module.distribution.distribution_arn]
      }]
    }
  }
}
```

Passing the distribution's ARN back into the same `module "origin_bucket"` call this way does not create a dependency cycle: only the bucket-policy resource inside that module depends on the distribution, not the bucket itself, which `module.distribution`'s `origin` input depends on. Terraform resolves cross-module references at the resource level, not the module-call level.

Point a Route 53 alias record at the distribution with `domain_name` and the fixed `hosted_zone_id` output, through `aws.modules.route53`.

## SSE-KMS origins: the key policy statement

`aws.modules.s3` defaults to `sse_algorithm = "aws:kms"` and, with `kms_key_arn = null`, to the **AWS managed** `aws/s3` key. CloudFront's OAC must be able to call `kms:Decrypt` on the key that encrypted an object, which takes a statement in that **key's policy**, not only in the bucket policy. So:

| Origin bucket encryption | What the caller must do |
| --- | --- |
| SSE-S3 (`AES256`) | Nothing beyond `required_bucket_policy_json`. |
| SSE-KMS under a **customer managed** key | Attach `required_bucket_policy_json` to the bucket **and** add `required_kms_key_policy_json` to the key's policy. |
| SSE-KMS under the **AWS managed `aws/s3`** key (`aws.modules.s3`'s default) | **Not usable with OAC.** An AWS managed key's policy cannot be edited, so CloudFront can never be granted `kms:Decrypt` on it. Use a customer managed key (`kms_key_arn`) or `sse_algorithm = "AES256"` for the origin bucket. |

`required_kms_key_policy_json` grants `cloudfront.amazonaws.com` only `kms:Decrypt` (the distribution only reads), scoped by the same `AWS:SourceArn` condition as the bucket statement, so no other distribution can decrypt with the key:

```hcl
data "aws_iam_policy_document" "origin_key" {
  # ...the key's existing statements (key administrators, the account root)...
  source_policy_documents = [jsonencode({
    Version   = "2012-10-17"
    Statement = [jsondecode(module.distribution.required_kms_key_policy_json)]
  })]
}

resource "aws_kms_key_policy" "origin" {
  key_id = aws_kms_key.origin.id
  policy = data.aws_iam_policy_document.origin_key.json
}
```

**Forgetting it fails closed, silently.** The distribution deploys, the bucket policy looks right, and every object request returns `403 AccessDenied` from the origin: safe, but nothing at plan or apply time says why. To detect it: request a known object through the distribution after deploy and expect a 200 (the integration suite does exactly this); a 403 on an object that exists, with `required_bucket_policy_json` attached, points at the key policy. S3 server access logs or CloudTrail data events show the underlying `kms:Decrypt` denial for the `cloudfront.amazonaws.com` principal.

## Quotas

CloudFront's default quotas that this module's inputs can run into (both adjustable through Service Quotas; the module does not validate them because the effective limit is per account):

| Quota | Default | Input |
| --- | --- | --- |
| Cache behaviors per distribution | 25 | `cache_behaviors` (the default behavior is separate) |
| Alternate domain names (CNAMEs) per distribution | 100 | `aliases` |

Exceeding either fails at apply time with a CloudFront `TooMany...` error, not at plan time.

## The CloudFront + ACM + WAF `us-east-1` constraint

CloudFront resources are global; this module needs no provider alias and creates its distribution with whatever provider (and region) the caller configures. Two of its *inputs*, however, are validated identifiers for resources that must have been created through a `us-east-1` provider regardless of that:

| Input | Must be created via `us-east-1` because | Validated here? |
| --- | --- | --- |
| `viewer_certificate_arn` | CloudFront reads custom-domain viewer certificates from ACM in `us-east-1` only, no matter where the distribution or its origin lives. | **Yes.** An ACM certificate ARN embeds its region as its fourth colon-separated segment, so a `validation` block checks that segment equals `us-east-1`. |
| `web_acl_arn` | A CLOUDFRONT-scope WAFv2 Web ACL (`aws.modules.waf`) must be created through a `us-east-1` provider, regardless of the origin bucket's or distribution's region. | **Yes.** AWS issues a CLOUDFRONT-scope Web ACL ARN as `arn:aws:wafv2:us-east-1:<account>:global/webacl/<name>/<id>`: the region segment is the real region `us-east-1`, and `global` appears only in the resource segment. A `validation` block checks both, so a `regional/webacl/` ARN (which cannot attach to CloudFront) or a CLOUDFRONT-shaped ARN naming another region is rejected at plan time. `<name>` accepts letters, digits, hyphens, and underscores, exactly what `aws.modules.waf` allows. |

v1.0.0 wrongly required the literal string `global` in the WAF ARN's *region* segment, a shape AWS never issues, so no real CLOUDFRONT-scope Web ACL could be attached; see [docs/DESIGN.md](docs/DESIGN.md) and [CHANGELOG.md](CHANGELOG.md).

## Architecture

```text
root (one distribution, one origin, one OAC)
├── variables.tf   Inputs grouped by concern: identity, origin, distribution
│                  behavior, cache behaviors, tags.
├── locals.tf      Tag merge, partition fallback, the fixed CloudFront hosted
│                  zone ID, the CachingOptimized default, cache-behavior
│                  default resolution, the bucket and KMS key policy statements.
├── main.tf        aws_cloudfront_origin_access_control.this,
│                  aws_cloudfront_distribution.this (dynamic
│                  ordered_cache_behavior, custom_error_response,
│                  viewer_certificate, logging_config), resource
│                  preconditions for the alias/certificate rule.
├── checks.tf      Advisory: access_logging_disabled, web_acl_not_attached.
└── outputs.tf     Identity, the fixed hosted zone ID, required_bucket_policy_json,
                   required_kms_key_policy_json.
```

`cache_behaviors` is an ordered **list** of objects, each with its own `path_pattern`. CloudFront evaluates ordered cache behaviors in the order it receives them and uses the **first** one whose pattern matches, so the list order is the precedence order: list a narrower pattern (`/static/images/*`) before a broader one that also matches it (`/static/*`), or the narrower one never matches. (v1.x took a map keyed by `path_pattern`, which rendered in lexical key order regardless of intent; see [docs/UPGRADE-2.0.md](docs/UPGRADE-2.0.md).) `path_pattern` must be non-empty and unique, and `"*"` is rejected because it is reserved for `default_cache_behavior`, configured as a separate input entirely. Both share the same settings (`allowed_methods`, `cached_methods`, `cache_policy_id`, `compress`), so a path pattern's behavior can be promoted to the default behavior, or vice versa, by moving the object (minus `path_pattern`), not rewriting it. `cache_policy_id` left `null` in either resolves to the AWS managed `CachingOptimized` policy (`658327ea-f89d-4fab-a63d-7e88639e58f6`).

## Usage patterns

| Example | What it shows |
| --- | --- |
| [`examples/minimal`](examples/minimal) | The smallest working call: default domain, no aliases, no WAF, every other default. |
| [`examples/custom-domain-with-waf`](examples/custom-domain-with-waf) | `aliases` plus a `us-east-1` ACM certificate and a CLOUDFRONT-scope WAF Web ACL ARN, with access logging turned on — the `us-east-1` constraint end to end. |
| [`examples/spa-with-error-rewrites`](examples/spa-with-error-rewrites) | `custom_error_responses` rewriting 403/404 to `/index.html` for a single-page application's client-side router, plus a `CachingDisabled` app shell alongside a long-lived `/static/*` cache behavior. |

## Security model

Origin access

- The origin bucket is never touched by this module: no bucket resource, no bucket policy attachment, no data-source read into it. `origin.bucket_name` and `origin.bucket_regional_domain_name` are plain identifiers the caller supplies, exactly like every other external dependency in this module series.
- `required_bucket_policy_json`'s `Condition.StringEquals["AWS:SourceArn"]` scopes the OAC's read access to *this* distribution's own ARN. Without it, the statement would grant `s3:GetObject` to the entire `cloudfront.amazonaws.com` service principal — any CloudFront distribution in the account, not just this one. This is the standard OAC trust pitfall, and the module's tests treat it as the single most important property to prove: `tests/bucket_policy.tftest.hcl` asserts it under `mock_provider` with `command = apply` (the ARN is unknown at plan time for a fresh create), and `tests/integration/smoke.tftest.hcl` asserts it again against the real API.
- The legacy Origin Access Identity is never used; `aws_cloudfront_origin_access_control` with `signing_behavior = "always"` and `signing_protocol = "sigv4"` is.

Transport and certificates

- `minimum_protocol_version` defaults to `TLSv1.2_2021`; every viewer connection is `redirect-to-https`.
- Exactly one viewer certificate path is ever configured: the CloudFront default certificate with no aliases, or a caller ACM certificate with SNI when aliases are set — enforced by two resource preconditions, not just a validation, so the rule holds even if a future edit changed how `aliases` or `viewer_certificate_arn` are derived.
- `viewer_certificate_arn`'s region segment is validated to be `us-east-1`; see [The `us-east-1` constraint](#the-cloudfront--acm--waf-us-east-1-constraint).

Perimeter

- `web_acl_arn` is optional but advised: the `web_acl_not_attached` check warns on every plan and apply while it is unset. Its ARN is validated as CLOUDFRONT-scope (`global/webacl/`) in `us-east-1` (see above).
- `geo_restriction` defaults to `none`; `whitelist` and `blacklist` both require a non-empty `locations` set of uppercase ISO 3166-1 alpha-2 codes.
- Standard access logging is optional but advised: the `access_logging_disabled` check warns while `logging` is unset.

Not created here

- The origin bucket, the viewer certificate, and the WAF Web ACL. Each has its own lifecycle and owner (`aws.modules.s3`, `aws.modules.acm`, `aws.modules.waf`). This module consumes their identifiers and creates only the distribution and its OAC.
- A second, ALB-backed origin type. See [Deferred to v2 in docs/DESIGN.md](docs/DESIGN.md#deferred-to-v2).

## Testing

Two layers, deliberately separate:

- **Contract tests** (`tests/`, run by `make test` and by CI) use `mock_provider` with `command = plan`, except `tests/bucket_policy.tftest.hcl`, which needs `command = apply` because `required_bucket_policy_json` is rendered from the distribution's ARN, unknown at plan time for a fresh create. 66 tests cover secure defaults, every validation and precondition (through `expect_failures`), real-shaped CLOUDFRONT-scope WAF ARNs, the default vs. custom-domain viewer certificate paths, geo restriction, custom error responses, cache behavior defaults, overrides, and list-order precedence, both advisory checks, and the `AWS:SourceArn` bucket-policy and KMS key-policy statements. The integration suite additionally fetches an object through the real distribution with and without the bucket policy.
- **Integration suite** (`tests/integration/`, run by `make integration-smoke` or the dispatch-only `integration` workflow) applies the module for real in **your** account: a disposable, private S3 bucket fixture (created plainly, not through `aws.modules.s3`, to keep the fixture minimal — this module's own tests must not depend on another module's interface), a minimal distribution against it, real-API assertions including the `AWS:SourceArn` condition again, then teardown. CloudFront distributions are slow both to create and to delete in real AWS (commonly 15-25 minutes each way, since `aws_cloudfront_distribution` waits for the `Deployed` state by default) — see [tests/integration/README.md](tests/integration/README.md) for why that is expected, not a hang.

## Design principles

- Single responsibility. One distribution, one origin, one OAC, one rendered bucket-policy statement. `main.tf` holds the resources, `locals.tf` the pure rendering logic, `checks.tf` the advisory posture.
- Open/closed. New cache behaviors, aliases, geo-restriction entries, and custom error responses arrive as data; no branch of the module needs editing to add one.
- Liskov substitution. Every `cache_behaviors` entry and `default_cache_behavior` share exactly the same object shape and default resolution.
- Interface segregation. A caller with no custom domain never touches `viewer_certificate_arn` or `minimum_protocol_version`; a caller with no SPA rewrites never touches `custom_error_responses`. Every optional feature is off until declared.
- Dependency inversion. The module depends on identifiers (`bucket_name`, `bucket_regional_domain_name`, a certificate ARN, a Web ACL ARN), never on how they were produced, and reads no data source except the one documented partition fallback.

The full rationale, including the ADR 0004 scope boundary and what was deliberately deferred to v2, is in [docs/DESIGN.md](docs/DESIGN.md).

## Compatibility and scope

- Terraform `>= 1.7.0, < 2.0.0`. AWS provider `>= 6.35.0, < 7.0.0`.
- Standard `aws` partition only. `partition` rejects `aws-cn` and `aws-us-gov`, and a looked-up partition other than `aws` fails a precondition: CloudFront in the China Regions supports neither Origin Access Control, ACM viewer certificates, nor AWS WAF, and AWS GovCloud (US) has no CloudFront.
- One CloudFront distribution, one private S3 origin, per module call. No provider alias is required by this module itself; `viewer_certificate_arn` and `web_acl_arn` are only valid when the caller created those specific resources through a `us-east-1` provider elsewhere.
- Static content delivery only, per ADR 0004. A second, ALB-backed origin type was considered and rejected for v1 — see [Deferred to v2 in docs/DESIGN.md](docs/DESIGN.md#deferred-to-v2).
- v2.0.0 changes the interface incompatibly (`cache_behaviors` is an ordered list, TLS 1.0/1.1 policies and non-`aws` partitions are rejected); see [docs/UPGRADE-2.0.md](docs/UPGRADE-2.0.md). Further additions arrive as optional inputs and outputs.

## Versioning and releases

Releases follow semantic versioning: incompatible interface changes bump the major version, new optional inputs and outputs bump the minor version, fixes bump the patch version. Every release is a signed annotated tag `vX.Y.Z`.

Pin the full commit SHA of the release tag and record the tag in a comment, so the source cannot move under you:

```hcl
module "distribution" {
  source = "git::https://github.com/hatan4ik/aws.modules.cloudfront.git?ref=<commit-sha>" # v1.0.0
}
```

The `module-release` workflow publishes an immutable GitHub release only from a GitHub-verified, signed, annotated semantic-version tag that points at the merged `main` revision; lightweight or unsigned tags are rejected before anything is published. With a GitHub-associated GPG or SSH signing key configured:

```bash
git fetch origin
git tag -s vX.Y.Z <commit> -m "vX.Y.Z"
git push origin vX.Y.Z
gh workflow run module-release.yml --ref vX.Y.Z -f release_tag=vX.Y.Z
```

Dispatch from the tag, never from `main`: the workflow verifies that the tag points at the revision it checked out. All changes are listed in [CHANGELOG.md](CHANGELOG.md).

## Contributing

Development setup, the local quality gate, the test-first workflow, and the release process are described in [CONTRIBUTING.md](CONTRIBUTING.md). Security reports go through [SECURITY.md](SECURITY.md).

## License

Apache-2.0. See [LICENSE](LICENSE).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7.0, < 2.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.35.0, < 7.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.35.0, < 7.0.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_cloudfront_distribution.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_distribution) | resource |
| [aws_cloudfront_origin_access_control.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_origin_access_control) | resource |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_aliases"></a> [aliases](#input\_aliases) | Custom domain names (CNAMEs) the distribution answers to, in addition to its own *.cloudfront.net domain. Empty by default, which uses the CloudFront default certificate; a non-empty set requires viewer\_certificate\_arn. | `set(string)` | `[]` | no |
| <a name="input_cache_behaviors"></a> [cache\_behaviors](#input\_cache\_behaviors) | Additional cache behaviors, evaluated before default\_cache\_behavior. CloudFront uses the FIRST behavior whose path\_pattern matches a request, and this list's order is exactly the order CloudFront receives them in: list a narrower pattern ("/static/images/*") before a broader one that also matches it ("/static/*"), or the narrower one never matches. path\_pattern must be non-empty and unique; "*" is reserved for default\_cache\_behavior and rejected here. cache\_policy\_id null (the default) uses the AWS managed CachingOptimized policy. CloudFront's default quota is 25 cache behaviors per distribution (adjustable through Service Quotas). | <pre>list(object({<br/>    path_pattern    = string<br/>    allowed_methods = optional(set(string), ["GET", "HEAD"])<br/>    cached_methods  = optional(set(string), ["GET", "HEAD"])<br/>    cache_policy_id = optional(string)<br/>    compress        = optional(bool, true)<br/>  }))</pre> | `[]` | no |
| <a name="input_custom_error_responses"></a> [custom\_error\_responses](#input\_custom\_error\_responses) | SPA-style rewrites of origin error responses, for example serving /index.html with a 200 for a 404 from the origin. error\_code is the origin's HTTP status; response\_code and response\_page\_path, when set, together override what the viewer receives; error\_caching\_min\_ttl (default 300) is how long CloudFront caches the error itself. | <pre>list(object({<br/>    error_code            = number<br/>    response_code         = optional(number)<br/>    response_page_path    = optional(string)<br/>    error_caching_min_ttl = optional(number, 300)<br/>  }))</pre> | `[]` | no |
| <a name="input_default_cache_behavior"></a> [default\_cache\_behavior](#input\_default\_cache\_behavior) | Cache behaviour for the distribution's default (path\_pattern = "*") behavior. cache\_policy\_id null (the default) uses the AWS managed CachingOptimized policy. | <pre>object({<br/>    allowed_methods = optional(set(string), ["GET", "HEAD"])<br/>    cached_methods  = optional(set(string), ["GET", "HEAD"])<br/>    cache_policy_id = optional(string)<br/>    compress        = optional(bool, true)<br/>  })</pre> | `{}` | no |
| <a name="input_default_root_object"></a> [default\_root\_object](#input\_default\_root\_object) | Object requested at the distribution root (for example when a viewer requests /). Must not start with /. | `string` | `"index.html"` | no |
| <a name="input_geo_restriction"></a> [geo\_restriction](#input\_geo\_restriction) | Geographic access restriction. restriction\_type none (the default) allows every viewer location; whitelist or blacklist require a non-empty locations set of ISO 3166-1 alpha-2 country codes. | <pre>object({<br/>    restriction_type = string<br/>    locations        = optional(set(string), [])<br/>  })</pre> | <pre>{<br/>  "restriction_type": "none"<br/>}</pre> | no |
| <a name="input_logging"></a> [logging](#input\_logging) | Standard CloudFront access logging to a caller-owned S3 bucket. Off (null) by default; a check block advises turning it on. This module does not create or configure the logging bucket's ACLs or bucket-owner-enforced ownership. | <pre>object({<br/>    bucket_domain_name = string<br/>    prefix             = optional(string)<br/>  })</pre> | `null` | no |
| <a name="input_minimum_protocol_version"></a> [minimum\_protocol\_version](#input\_minimum\_protocol\_version) | CloudFront security policy (minimum TLS version and ciphers) for viewers when a custom viewer certificate is used (aliases non-empty). Accepts the TLS 1.2+ policies TLSv1.2\_2018, TLSv1.2\_2019, TLSv1.2\_2021 (the default), TLSv1.2\_2025, and TLSv1.3\_2025 (TLS 1.3 only); policies allowing deprecated TLS 1.0/1.1 are rejected. Ignored when the distribution uses the default certificate, which CloudFront always serves at its own fixed minimum version. | `string` | `"TLSv1.2_2021"` | no |
| <a name="input_name"></a> [name](#input\_name) | Human-readable identifier for the distribution. CloudFront distributions have no name argument: this value becomes the distribution's comment, the Origin Access Control's name, and the default Name tag. At most 64 characters (the tighter of the two limits it drives) using letters, digits, spaces, dots, underscores, and hyphens. | `string` | n/a | yes |
| <a name="input_origin"></a> [origin](#input\_origin) | The single S3 origin this distribution serves. bucket\_name and bucket\_regional\_domain\_name come from the bucket the caller owns (for example aws.modules.s3's aws\_s3\_bucket.this.bucket and .bucket\_regional\_domain\_name outputs); this module never creates or reaches into that bucket. origin\_path, when set, must start with / and not end with /, and scopes both the CloudFront origin path and the required\_bucket\_policy\_json output's Resource to that prefix. | <pre>object({<br/>    bucket_name                 = string<br/>    bucket_regional_domain_name = string<br/>    origin_path                 = optional(string, "")<br/>  })</pre> | n/a | yes |
| <a name="input_partition"></a> [partition](#input\_partition) | AWS partition of the origin bucket's account, used only to render the Resource ARN in required\_bucket\_policy\_json. Only the standard "aws" partition is supported: CloudFront in the China Regions (aws-cn) supports neither Origin Access Control (this module's only origin access mechanism), ACM viewer certificates, nor AWS WAF, and AWS GovCloud (US) has no CloudFront, so a distribution this module builds cannot work in either. Any other value is rejected here, and a looked-up partition other than aws fails a precondition. Null reads it through aws\_partition; pass "aws" to skip the lookup. | `string` | `null` | no |
| <a name="input_price_class"></a> [price\_class](#input\_price\_class) | Edge locations that serve the distribution. PriceClass\_100 (the default) is the cheapest: US, Canada, and Europe only. Opt into PriceClass\_200 (adds Asia, Africa, Oceania) or PriceClass\_All explicitly. | `string` | `"PriceClass_100"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the distribution. The module adds a Name tag (from name) only when you do not set one, and never overrides caller tags. | `map(string)` | `{}` | no |
| <a name="input_viewer_certificate_arn"></a> [viewer\_certificate\_arn](#input\_viewer\_certificate\_arn) | ACM certificate ARN presented to viewers for a custom domain. Required when aliases is non-empty and forbidden when it is empty (the default *.cloudfront.net certificate already covers that case). CloudFront only ever reads viewer certificates from us-east-1, regardless of the origin bucket's region or this module's own provider region, so the ARN's region segment is validated here; the certificate itself must actually have been requested through a us-east-1 provider (see aws.modules.acm's cloudfront example) since Terraform cannot inspect where an ARN's resource was created, only what the ARN string says. | `string` | `null` | no |
| <a name="input_web_acl_arn"></a> [web\_acl\_arn](#input\_web\_acl\_arn) | ARN of a CLOUDFRONT-scope WAFv2 Web ACL (for example aws.modules.waf's web\_acl\_arn output with scope = "CLOUDFRONT") to associate with the distribution. Optional, but a check block advises setting it: ADR 0004 places a global WAF at every entry layer. AWS issues a CLOUDFRONT-scope Web ACL's ARN as arn:<partition>:wafv2:us-east-1:<account>:global/webacl/<name>/<id>: the region segment is the real region us-east-1 (the only region WAFv2 accepts CLOUDFRONT-scope ACLs from) and "global" appears only in the resource segment. Both are validated, so a REGIONAL-scope ARN (regional/webacl/...) or a CLOUDFRONT-shaped ARN naming any other region is rejected at plan time. <name> accepts letters, digits, hyphens, and underscores, the same characters aws.modules.waf and the WAFv2 API allow. See docs/DESIGN.md. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_distribution_arn"></a> [distribution\_arn](#output\_distribution\_arn) | ARN of the distribution. Also the value scoped into required\_bucket\_policy\_json's AWS:SourceArn condition. |
| <a name="output_distribution_id"></a> [distribution\_id](#output\_distribution\_id) | ID of the distribution. |
| <a name="output_domain_name"></a> [domain\_name](#output\_domain\_name) | Distribution's own *.cloudfront.net domain name. Use this, or a custom alias, as the target of a DNS record. |
| <a name="output_hosted_zone_id"></a> [hosted\_zone\_id](#output\_hosted\_zone\_id) | CloudFront's fixed alias-target hosted zone ID (Z2FDTNDATAQYW2 in the standard aws partition), for a Route 53 alias record via aws.modules.route53. It identifies CloudFront as an alias target class, not a zone this distribution owns. |
| <a name="output_origin_access_control_id"></a> [origin\_access\_control\_id](#output\_origin\_access\_control\_id) | ID of the Origin Access Control this distribution reads the S3 origin through. |
| <a name="output_required_bucket_policy_json"></a> [required\_bucket\_policy\_json](#output\_required\_bucket\_policy\_json) | The exact IAM policy STATEMENT (not a full policy document) the origin bucket needs, as a JSON string: grants cloudfront.amazonaws.com s3:GetObject on the origin path, scoped by a Condition.StringEquals["AWS:SourceArn"] to this distribution's own ARN. Merge it (jsondecode it first) into a standalone aws\_s3\_bucket\_policy's statement list, or translate it into aws.modules.s3's own typed bucket\_policy\_statements input (its principals and conditions fields have a different shape than raw IAM JSON); this module cannot attach it itself because it does not own the bucket. A missing or wrong SourceArn here would let any CloudFront distribution in the account read the bucket, not just this one. |
| <a name="output_required_bucket_policy_statement"></a> [required\_bucket\_policy\_statement](#output\_required\_bucket\_policy\_statement) | The same origin-read grant as required\_bucket\_policy\_json (same Sid, principal, action, resource, and AWS:SourceArn condition, derived from the same local), but as a plain object keyed by its Sid in exactly the map-entry shape of aws.modules.s3's bucket\_policy\_statements input, so it needs no translation: bucket\_policy\_statements = merge(module.distribution.required\_bucket\_policy\_statement, { ...other statements... }). |
| <a name="output_required_kms_key_policy_json"></a> [required\_kms\_key\_policy\_json](#output\_required\_kms\_key\_policy\_json) | The KMS key-policy STATEMENT (not a full policy document) the origin bucket's encryption key needs when objects are encrypted with SSE-KMS (aws:kms or aws:kms:dsse) under a CUSTOMER MANAGED key, as a JSON string: grants cloudfront.amazonaws.com kms:Decrypt, scoped by Condition.StringEquals["AWS:SourceArn"] to this distribution's own ARN. Add it (jsondecode it first) to that key's policy. Not needed for SSE-S3 (AES256). It cannot be used with the AWS managed aws/s3 key, whose key policy cannot be edited: OAC cannot read objects encrypted under aws/s3, so use a customer managed key or SSE-S3 instead (aws.modules.s3 defaults to aws:kms with aws/s3 when kms\_key\_arn is null). Without this statement CloudFront fails closed: every object request returns 403 AccessDenied. |
| <a name="output_required_kms_key_policy_statement"></a> [required\_kms\_key\_policy\_statement](#output\_required\_kms\_key\_policy\_statement) | The same kms:Decrypt grant as required\_kms\_key\_policy\_json (same Sid, principal, action, Resource "*", and AWS:SourceArn condition, derived from the same local), but as a plain object keyed by its Sid in exactly the map-entry shape of aws.modules.kms's policy\_statements input (modules/key-policy's statements), so it needs no translation: policy\_statements = merge(module.distribution.required\_kms\_key\_policy\_statement, { ...other statements... }). Same caveats as the JSON output: only for a customer managed key, never the AWS managed aws/s3 key. |
<!-- END_TF_DOCS -->
