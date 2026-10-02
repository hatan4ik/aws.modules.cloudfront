# Integration probe

Used by the smoke suite in the parent directory to prove the module's
Origin Access Control read path against real AWS, not just that the rendered
`required_bucket_policy_json` string looks right. It optionally attaches that
statement to the fixture bucket as the bucket's only policy statement, waits
for it to settle, and fetches a known object through the distribution with
the `http` data source. The smoke suite runs it twice:

1. `attach_bucket_policy = false`: the bucket has no policy, so CloudFront's
   signed OAC request is denied and the distribution returns `403`.
2. `attach_bucket_policy = true`: the module's own statement is the bucket's
   only grant, so a `200` with the exact object body proves that statement
   (including its `AWS:SourceArn` condition matching this real distribution)
   is sufficient.

It is short-lived test scaffolding, not a deployable pattern, and is excluded
from policy scans (see `.checkov.yml` and `trivy.yaml` at the repository root).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7.0, < 2.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.35.0, < 7.0.0 |
| <a name="requirement_http"></a> [http](#requirement\_http) | >= 3.4.0, < 4.0.0 |
| <a name="requirement_time"></a> [time](#requirement\_time) | >= 0.11.0, < 1.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.35.0, < 7.0.0 |
| <a name="provider_http"></a> [http](#provider\_http) | >= 3.4.0, < 4.0.0 |
| <a name="provider_time"></a> [time](#provider\_time) | >= 0.11.0, < 1.0.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_s3_bucket_policy.origin](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [time_sleep.settle](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/sleep) | resource |
| [http_http.probe](https://registry.terraform.io/providers/hashicorp/http/latest/docs/data-sources/http) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_attach_bucket_policy"></a> [attach\_bucket\_policy](#input\_attach\_bucket\_policy) | true attaches bucket\_policy\_statement\_json to the bucket (and waits settle\_seconds) before probing; false probes with no bucket policy at all. | `bool` | n/a | yes |
| <a name="input_bucket_name"></a> [bucket\_name](#input\_bucket\_name) | Name of the fixture origin bucket the policy is attached to. | `string` | n/a | yes |
| <a name="input_bucket_policy_statement_json"></a> [bucket\_policy\_statement\_json](#input\_bucket\_policy\_statement\_json) | The module under test's required\_bucket\_policy\_json output: one IAM policy statement, as JSON. | `string` | n/a | yes |
| <a name="input_settle_seconds"></a> [settle\_seconds](#input\_settle\_seconds) | Seconds to wait after attaching the policy before probing. Covers S3 bucket-policy propagation and CloudFront's default 10 second caching of the earlier 403 for the same object. | `number` | `90` | no |
| <a name="input_url"></a> [url](#input\_url) | HTTPS URL of the probe object, served through the distribution under test. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_body"></a> [body](#output\_body) | Response body CloudFront returned for the probe object. |
| <a name="output_bucket_policy_attached"></a> [bucket\_policy\_attached](#output\_bucket\_policy\_attached) | Whether this probe ran with the module's bucket-policy statement attached. |
| <a name="output_status_code"></a> [status\_code](#output\_status\_code) | HTTP status code CloudFront returned for the probe object. |
<!-- END_TF_DOCS -->
