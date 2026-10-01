# Design: aws.modules.cloudfront v1

Status: accepted 2026-09-27. Brand new module, no v0.x baseline.

## Purpose

`aws.modules.cloudfront` provisions **one** CloudFront distribution per module
call, serving **one** private S3 origin through an Origin Access Control
(OAC). It is the static half of
[ADR 0004](/docs/adr/0004-edge-ingress-and-egress.md)'s edge architecture:
"CloudFront plus a global WAF delivers static content from private S3
origins." The dynamic half — Global Accelerator to regional WAF-protected
ALBs — is a separate module, `aws.modules.global-accelerator`, built
alongside this one.

The module creates:

- One `aws_cloudfront_origin_access_control` (OAC, not the legacy Origin
  Access Identity).
- One `aws_cloudfront_distribution` with a default cache behavior, any number
  of additional ordered cache behaviors keyed by path pattern, geographic
  restriction, custom error responses, optional access logging, and an
  optional WAF Web ACL association.
- A rendered IAM policy **statement** (not a full document) that the caller
  merges into the origin bucket's own policy.

It deliberately does **not**:

- Create, own, or reach into the origin S3 bucket, or attach a policy to it.
  The bucket is a dependency the caller names by `bucket_name` and
  `bucket_regional_domain_name` (typically `aws.modules.s3`'s own outputs),
  exactly like every other identifier this module series consumes. OAC's IAM
  trust model needs one extra step beyond a plain ARN input, though: the
  bucket's *own* policy must grant this distribution's OAC read access, and
  only the bucket's owner can write that policy. This module cannot safely
  reach into a bucket it does not own to attach one, so instead it renders
  the exact statement the bucket needs (`required_bucket_policy_json`) and
  leaves the caller to merge it in, through a plain `aws_s3_bucket_policy`
  (`jsondecode` the statement into its `Statement` list) or by translating it
  into `aws.modules.s3`'s own `bucket_policy_statements` input, whose
  `principals` and `conditions` fields have a different shape than raw IAM
  JSON and so cannot be merged in directly. See the README's Quick start for
  both patterns worked out in full.
- Serve a second, ALB-backed origin type. See "Deferred to v2" below.
- Request the viewer certificate or the WAF Web ACL. Both are separate
  resources with their own lifecycle (`aws.modules.acm`,
  `aws.modules.waf`), and both carry the `us-east-1` constraint described
  next.

## CloudFront distributions have no `name` argument

There is no `name` variable that maps onto a distribution's `Name` API field,
because CloudFront does not have one. `var.name` instead becomes three
things: the distribution's `comment` (its closest analog to a name in the
CloudFront console), the OAC's own `name` (which — unlike the distribution —
*is* a uniqueness-enforced identifier, hence `var.name`'s tighter 64-character
limit), and the default `Name` tag. A caller used to a `name` input that
becomes a resource's actual `Name` argument should read `comment` in the
generated docs as that same value, not a separate concept.

## The CloudFront + ACM + WAF `us-east-1` constraint

CloudFront resources are global; this module needs no provider alias and
creates its distribution with whatever provider (and region) the caller
configures. But two of its *inputs* are validated identifiers for resources
that must have been created through a `us-east-1` provider regardless of that:

| Input | Must be created via `us-east-1` because | Validated here? |
| --- | --- | --- |
| `viewer_certificate_arn` | CloudFront reads custom-domain viewer certificates from ACM in `us-east-1` only, no matter where the distribution or its origin lives. | **Yes.** An ACM certificate ARN embeds its region as its fourth colon-separated segment (`arn:aws:acm:us-east-1:...`), so the variable's own `validation` block checks that segment equals `us-east-1` with `can(regex(...))`. This is a real, load-bearing check: a certificate requested in the wrong region fails exactly this way in practice. |
| `web_acl_arn` | A CLOUDFRONT-scope WAFv2 Web ACL must be created through a `us-east-1` provider (`aws.modules.waf`'s `region = "us-east-1"` requirement for `scope = "CLOUDFRONT"`), regardless of the origin bucket's or distribution's region. | **Yes.** AWS issues a CLOUDFRONT-scope Web ACL ARN as `arn:<partition>:wafv2:us-east-1:<account>:global/webacl/<name>/<id>` (the WAFv2 developer guide's own example is `arn:aws:wafv2:us-east-1:111122223333:global/webacl/ExampleWebACL/<uuid>`). The region segment carries the real region, `us-east-1`; the literal `global` appears only in the *resource* segment, as the scope marker. The variable's `validation` therefore checks both: the region segment equals `us-east-1`, and the resource segment says `global/webacl/` (rejecting a `regional/webacl/` ARN, which cannot be attached to a CloudFront distribution). |

**Correction (v2.0.0).** v1.0.0 of this document claimed the opposite: that a
CLOUDFRONT-scope ARN carries the literal string `global` in its *region*
segment, so its `us-east-1` origin "leaves no trace in the ARN" and could not
be validated. That was factually wrong, and the validation built on it
(`^arn:...:wafv2:global:...`) rejected every CLOUDFRONT-scope Web ACL ARN AWS
actually issues — including `aws.modules.waf`'s real output — so the
WAF-on-CloudFront composition ADR 0004 calls for was impossible through these
two modules. Every test and example used a fabricated ARN of the same wrong
shape, which is why it went unnoticed. Both inputs' `us-east-1` constraints are
in fact provable from their ARNs, and both are now validated the same way.

The Web ACL `<name>` segment accepts `[a-zA-Z0-9_-]{1,128}`: letters, digits,
hyphens, and underscores, matching what `aws.modules.waf` and the WAFv2 API
(`^[\w\-]+$`, 1-128 characters) allow, so an ACL legitimately named, say,
`api_acl` composes. `aws.modules.alb`'s REGIONAL-scope validation uses the same
character class.

## `required_bucket_policy_json` and `AWS:SourceArn`

This output is the module's single most security-critical piece of behavior.
It is a `jsonencode`-able IAM policy **statement** — not a full policy
document — because the caller must merge it with whatever other statements
already govern the origin bucket (deny-insecure-transport, SSE enforcement,
other principals), and a full document would silently clobber those on
merge. The statement:

```json
{
  "Sid": "AllowCloudFrontServicePrincipalReadOnly",
  "Effect": "Allow",
  "Principal": { "Service": "cloudfront.amazonaws.com" },
  "Action": "s3:GetObject",
  "Resource": "arn:aws:s3:::<bucket>[<origin_path>]/*",
  "Condition": {
    "StringEquals": { "AWS:SourceArn": "<this distribution's own ARN>" }
  }
}
```

The `Condition.StringEquals["AWS:SourceArn"]` is what scopes the grant to
*this* distribution. Without it, the statement would grant
`s3:GetObject` to the entire `cloudfront.amazonaws.com` service principal —
meaning any CloudFront distribution in the AWS account, including ones this
module never created and the caller may not even control, could read every
object the statement's `Resource` covers. This is the standard OAC trust
pitfall (AWS's own OAC documentation calls it out), and it is why the module
does not stop at "grants the OAC service principal read access" and treats
the `SourceArn` condition as non-optional, unconditional, and always present.

`aws_cloudfront_distribution.this.arn` is unknown at plan time for a fresh
`create` — Terraform cannot know a distribution's ARN before AWS assigns one
— so `required_bucket_policy_json`, which is rendered from that ARN, is also
unknown at plan time. This makes it untestable with `command = plan` under
`mock_provider` the way every other output in this module is tested.
`tests/bucket_policy.tftest.hcl` instead uses `command = apply` with an
explicit `mock_resource "aws_cloudfront_distribution" { defaults = { arn =
"..." } }` override, so the mocked apply produces a known ARN the test can
assert against, exactly the pattern `aws.modules.ecs` used for a computed
KMS key ARN threaded into a policy document. That file is deliberately kept
separate from every `command = plan` file in `tests/`: `run` blocks in one
`.tftest.hcl` file share state, and an `apply` run's state leaking into a
later `plan` run in the same file would make a value the plan run expects to
be unknown appear unexpectedly known (or vice versa), quietly changing what
that run is actually testing.

## Interface

- `name` — required; see above.
- `origin` — required: `bucket_name`, `bucket_regional_domain_name` (both
  from the bucket the caller owns), `origin_path` (optional, must start with
  `/` and not end with `/`). Scopes both the CloudFront origin path and
  `required_bucket_policy_json`'s `Resource`.
- `partition` — optional; falls back to `data.aws_partition` only to render
  `required_bucket_policy_json`'s `Resource` ARN. The one documented
  exception to "no data sources," following `aws.modules.ksm`'s precedent for
  the same reasoning.
- `price_class`, `default_root_object`, `aliases`, `viewer_certificate_arn`,
  `minimum_protocol_version`, `web_acl_arn`, `geo_restriction`, `logging`,
  `custom_error_responses`, `default_cache_behavior`, `cache_behaviors`,
  `tags` — see the README's generated reference for full descriptions,
  defaults, and validations.

`cache_behaviors` is a map keyed by `path_pattern`. `"*"` is rejected as a key
(a variable validation) because it is reserved for `default_cache_behavior`,
configured as a separate input entirely — CloudFront's own model already
treats the default behavior specially (it is the fallback with no
`path_pattern` of its own), and letting a caller spell that out as a
`cache_behaviors["*"]` entry would create two different-looking ways to
configure the same thing with different validation paths.

`cache_policy_id` in both `default_cache_behavior` and every `cache_behaviors`
entry defaults (when left `null`) to the AWS managed **CachingOptimized**
policy (`658327ea-f89d-4fab-a63d-7e88639e58f6`), a sane default for static
content: long TTLs, gzip/br negotiated. A caller who needs different caching
supplies their own managed or customer-managed policy ID.

## Outputs

`distribution_id`, `distribution_arn`, `domain_name`, `hosted_zone_id`,
`origin_access_control_id`, `required_bucket_policy_json`. `hosted_zone_id`
is a fixed constant (`Z2FDTNDATAQYW2`), not a resource attribute lookup: it
identifies "an alias target is a CloudFront distribution" to Route 53, the
same value for every distribution in the standard `aws` partition, documented
by AWS rather than something this module could look up per-distribution. It
is deliberately a `local`, not `aws_cloudfront_distribution.this.hosted_zone_id`,
so that it stays knowable at plan time instead of turning every output into an
apply-only assertion in `tests/`.

## Deferred to v2

**A second, ALB-backed origin type was considered and rejected for v1.**
ADR 0004 explicitly separates static delivery (CloudFront/WAF to private S3)
from dynamic API delivery (Global Accelerator to regional WAF-protected
ALBs) as two different decisions with two different reviewers' sign-off. A
"just add an ALB origin option" extension would blur that explicit
separation inside a single module, and — more concretely — this module's
tests and examples could not prove anything meaningful about a routing policy
between origin types (which paths go to S3 versus which go to an ALB) without
inventing behavior the ADR never specified. If a future need genuinely
requires one distribution multiplexing both origin types, that is a decision
for whoever owns ADR 0004's next revision, not something this module should
back into unilaterally.

## Principles and how the module applies them

- **Single responsibility.** One distribution, one origin, one OAC, one
  rendered bucket-policy statement. `main.tf` holds the resources,
  `locals.tf` the pure rendering logic, `checks.tf` the advisory posture.
- **Open/closed.** New cache behaviors, aliases, geo-restriction entries, and
  custom error responses arrive as data (map/set/list entries); no branch of
  the module needs editing to add one.
- **Liskov substitution.** Every `cache_behaviors` entry and
  `default_cache_behavior` share exactly the same object shape and default
  resolution (`allowed_methods`, `cached_methods`, `cache_policy_id`,
  `compress`), so a path pattern's behavior can be promoted to the default
  behavior (or vice versa) by moving the object, not rewriting it.
- **Interface segregation.** A caller with no custom domain never touches
  `viewer_certificate_arn` or `minimum_protocol_version`; a caller with no
  need for SPA-style rewrites never touches `custom_error_responses`. Every
  optional feature is off until declared.
- **Dependency inversion.** The module depends on identifiers (`bucket_name`,
  `bucket_regional_domain_name`, a certificate ARN, a Web ACL ARN), never on
  how they were produced, and reads no data source except the one documented
  partition fallback.

## Architecture

```text
root (one distribution, one origin, one OAC)
├── variables.tf   Inputs grouped by concern: identity, origin, distribution
│                  behavior, cache behaviors, tags.
├── locals.tf      Tag merge, partition fallback, the fixed CloudFront hosted
│                  zone ID, the CachingOptimized default, cache-behavior
│                  default resolution, the bucket policy statement.
├── main.tf        aws_cloudfront_origin_access_control.this,
│                  aws_cloudfront_distribution.this (dynamic
│                  ordered_cache_behavior, custom_error_response,
│                  viewer_certificate, logging_config), resource
│                  preconditions for the alias/certificate rule.
├── checks.tf      Advisory: access_logging_disabled, web_acl_not_attached.
└── outputs.tf     Identity, the fixed hosted zone ID, required_bucket_policy_json.
```

## Testing strategy

- Contract tests (`tests/*.tftest.hcl`) use `mock_provider` with
  `command = plan`, except `tests/bucket_policy.tftest.hcl`, which needs
  `command = apply` for the reason above.
- Coverage: secure defaults; every variable validation and the two
  alias/certificate resource preconditions via `expect_failures`; the default
  vs. custom-domain viewer certificate paths; geo restriction (whitelist,
  blacklist, and their locations requirement); custom error responses
  (defaults and overrides); cache behavior defaults (the managed
  CachingOptimized policy ID applied when not overridden) and overrides;
  both advisory checks; and the `AWS:SourceArn` bucket-policy statement,
  including a caller-supplied `partition` and a non-empty `origin_path`.
- Examples are initialized, validated, linted, and scanned in CI like every
  other directory in the quality matrix.
- An integration suite (`tests/integration/smoke.tftest.hcl`) applies a real,
  minimal distribution against a throwaway plain `aws_s3_bucket` fixture (not
  `aws.modules.s3`, to keep the fixture minimal) and destroys it. CloudFront
  distribution deletion is slow in real AWS (commonly 15+ minutes once
  disabled first); `tests/integration/README.md` documents this as an
  expected slow suite, not a hang.

## Compatibility

- Terraform `>= 1.7.0, < 2.0.0`. AWS provider `>= 6.35.0, < 7.0.0`.
- No provider alias is required by this module itself; `viewer_certificate_arn`
  and `web_acl_arn` are only valid when the caller created those specific
  resources through a `us-east-1` provider elsewhere.

## Migration

Not applicable: this is a new module with no prior release. There is no
`docs/UPGRADE-1.0.md`.
