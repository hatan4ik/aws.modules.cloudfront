# Security policy

## Supported versions

| Version | Supported |
| --- | --- |
| 1.x | Yes. Security fixes and functional fixes on the latest minor release. |
| Unreleased `main` | Not supported for production use. |

## Reporting a vulnerability

Use GitHub private vulnerability reporting on this repository: open the Security tab and choose "Report a vulnerability". Do not open a public issue, pull request, or discussion for a security problem.

Include the module version or commit SHA, the inputs that reproduce the problem, the resulting plan, and the impact you see. Redact bucket names, certificate and Web ACL ARNs, and distribution IDs.

## What counts

- A wrong or missing `AWS:SourceArn` condition in `required_bucket_policy_json`: this is the module's single most security-critical output, and a defect here would let any CloudFront distribution in the account read the origin bucket, not just this one, if a caller merges the rendered statement in good faith.
- A module default that weakens security: a minimum TLS protocol version below `TLSv1.2_2021` applied silently, HTTP viewer traffic accepted instead of redirected, the legacy Origin Access Identity used instead of OAC.
- A validation bypass: an input the module claims to reject at plan time (the alias/certificate mutual requirement, an ACM ARN outside `us-east-1`, a `REGIONAL`-scope Web ACL ARN, an unrestricted `geo_restriction` missing its `locations`) that reaches the provider instead.
- A viewer-certificate precondition bypass: a distribution left with neither the default certificate nor a caller ACM certificate, or with both simultaneously.
- A dependency problem in the release pipeline that could publish unverified code.

Findings in your own inputs (for example a Web ACL you chose not to attach, since `web_acl_arn` is optional) or in AWS services themselves are out of scope here; report the latter to AWS. The module's inability to validate that `web_acl_arn` was created through a `us-east-1` provider is a documented, deliberate limitation (see [docs/DESIGN.md](docs/DESIGN.md)), not a vulnerability report.

## Response

We acknowledge a report within 5 business days and keep you informed while we confirm, fix, and release. A fix ships as a patch release with a `CHANGELOG.md` entry that credits the reporter unless they ask otherwise. Please give us a reasonable window before disclosing publicly.

## Security design

The module is secure by default: `TLSv1.2_2021` minimum protocol version, HTTPS-only viewer traffic, OAC (never the legacy Origin Access Identity) with the `AWS:SourceArn` condition always present and non-optional in `required_bucket_policy_json`, exactly one of the two viewer-certificate paths enforced by resource preconditions, `PriceClass_100` by default, advisory checks for missing access logging and a missing WAF Web ACL, plan-time validation of every input that can be checked at plan time, and no data source beyond one documented partition fallback. Every claim is enforced by a validation, a precondition, or a `check` block with a `terraform test` case behind it — including `tests/integration/smoke.tftest.hcl`, which proves the `AWS:SourceArn` condition again against the real CloudFront API, not just a mock. The full description is in the [Security model](README.md#security-model) section of the README, and the reasoning in [docs/DESIGN.md](docs/DESIGN.md).
