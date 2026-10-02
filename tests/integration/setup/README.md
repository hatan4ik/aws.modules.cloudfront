# Integration fixture

Disposable prerequisites for the smoke suite in the parent directory: a
private S3 bucket with a globally unique name (a prefix plus a random
suffix), every public access block on, bucket-owner-enforced ownership, and
identifying tags. `aws.modules.cloudfront` never creates or reaches into its
origin bucket (see `docs/DESIGN.md`), so unlike `aws.modules.s3`'s own
integration fixture - which creates no AWS resource, because the module
under test creates the bucket itself - this fixture creates the bucket
plainly, not through `aws.modules.s3`, to keep it minimal. `terraform test`
evaluates it before the module under test and destroys it afterwards. It is
not a deployable pattern and is excluded from policy scans (see
`.checkov.yml` and `trivy.yaml` at the repository root).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7.0, < 2.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.35.0, < 7.0.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | >= 3.6.0, < 4.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.35.0, < 7.0.0 |
| <a name="provider_random"></a> [random](#provider\_random) | >= 3.6.0, < 4.0.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_s3_bucket.origin](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_ownership_controls.origin](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_public_access_block.origin](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_object.probe](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object) | resource |
| [random_id.suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/id) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix of the disposable origin bucket name; a random suffix is appended so concurrent runs never collide. Include only characters valid in a bucket name. | `string` | `"cloudfront-it"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the origin bucket in addition to the identifying defaults. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_bucket_arn"></a> [bucket\_arn](#output\_bucket\_arn) | ARN of the disposable origin bucket, used by the smoke suite to attach the module's required\_bucket\_policy\_json statement. |
| <a name="output_bucket_name"></a> [bucket\_name](#output\_bucket\_name) | Name of the disposable origin bucket. |
| <a name="output_bucket_regional_domain_name"></a> [bucket\_regional\_domain\_name](#output\_bucket\_regional\_domain\_name) | Regional domain name of the disposable origin bucket, the module under test's origin.bucket\_regional\_domain\_name input. |
| <a name="output_probe_object_body"></a> [probe\_object\_body](#output\_probe\_object\_body) | Exact body of the probe object, which a successful fetch through the distribution must return. |
| <a name="output_probe_object_key"></a> [probe\_object\_key](#output\_probe\_object\_key) | Key of the known object the smoke suite fetches through the distribution. |
| <a name="output_tags"></a> [tags](#output\_tags) | Identifying tags applied to the origin bucket. |
<!-- END_TF_DOCS -->
