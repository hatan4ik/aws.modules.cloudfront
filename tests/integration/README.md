# Integration suites

The suite in this directory applies the module for real in **your** AWS
account and destroys everything afterwards. It complements the contract
tests in `tests/`, which run with `mock_provider`, need no credentials, and
use the AWS documentation placeholder account `123456789012` and placeholder
ARNs on purpose: they prove the module's interface and rendering, not that
AWS accepts it. This suite proves the latter.

Nothing here is tied to an account, region, or landing zone. Credentials and
the region come from the environment; the only prerequisite is a globally
unique origin bucket name, which [`setup/`](setup/) generates with a random
suffix so concurrent runs never collide. The fixture creates a plain,
private S3 bucket directly (not through `aws.modules.s3`), since this module
never creates or reaches into its own origin bucket - see
[docs/DESIGN.md](../../docs/DESIGN.md).

| Suite | What it proves | Needs | Typical time |
| --- | --- | --- | --- |
| `smoke.tftest.hcl` | A distribution with the module's defaults (no aliases, the default `*.cloudfront.net` certificate, `PriceClass_100`, no WAF, no logging) is accepted by the real CloudFront API against the fixture bucket, `hosted_zone_id` still matches the fixed constant asserted under `mock_provider`, and - the module's most important correctness property - `required_bucket_policy_json`'s `AWS:SourceArn` equals this real distribution's own ARN. The OAC read path is then proven end to end through [`probe/`](probe/): a known object fetched through the distribution returns `403` with no bucket policy, and `200` with its exact body once the module's rendered statement is attached as the bucket's only grant. | credentials, region | 15-25 minutes each way |

**CloudFront distributions are slow, both to create and to delete.**
`aws_cloudfront_distribution` waits for the distribution to reach `Deployed`
on create and (once disabled first) on destroy by default
(`wait_for_deployment`), which commonly takes 15-25 minutes in each
direction for a real distribution. A `terraform test` run against this suite
sitting quietly for that long is the suite working as expected, not a hang;
budget accordingly (the dispatch-only `integration` workflow's
`timeout-minutes: 60` already does).

## Run it in your account

```bash
export AWS_PROFILE=<your profile>   # or AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY / AWS_SESSION_TOKEN
export AWS_REGION=<region>
make integration-smoke              # terraform init -test-directory=tests/integration && terraform test -test-directory=tests/integration -filter=tests/integration/smoke.tftest.hcl
```

The credentials need the permissions in
[`iam/integration-permissions-policy.json`](iam/integration-permissions-policy.json).
The S3 statement is scoped to bucket names starting with `cloudfront-it-`,
which the fixture produces; the CloudFront statement cannot be scoped to the
disposable distribution the same way, because `CreateDistribution` and
`CreateOriginAccessControl` have no resource-level permissions to scope to
before the distribution or the OAC exists.

`terraform test` runs `tests/` only by default, so this suite never runs in
the credential-free quality pipeline. The fixture and probe modules are excluded from
the Checkov and Trivy scans (`.checkov.yml`, `trivy.yaml`) because it is
short-lived test scaffolding, not a deployable pattern.

## Run it from GitHub Actions (owner lane)

The `integration` workflow (`.github/workflows/integration.yml`) is
dispatch-only and assumes a role through GitHub OIDC. It reads everything
account-specific from the protected `integration` environment of the
repository, so the code stays universal:

| Environment variable | Meaning |
| --- | --- |
| `AWS_INTEGRATION_ROLE_ARN` | Role the workflow assumes. Trust policy: [`iam/github-oidc-trust-policy.json`](iam/github-oidc-trust-policy.json) with `<OWNER>/<REPO>` set to this repository; permissions: the policy above. |
| `AWS_INTEGRATION_REGION` | Region for the disposable bucket and distribution. |

Dispatch with `gh workflow run integration.yml -f suite=smoke`. Protect the
environment with required reviewers so a run cannot be started from a pull
request by anyone with write access.

For this repository's owner the environment is prepared with the sandbox
region; the role ARN is added once the role exists in the sandbox account,
created through the platform's delivery IAM module with the trust policy
above and the subject
`repo:hatan4ik/aws.modules.cloudfront:environment:integration`.
