# Minimal distribution

The smallest working call of `aws.modules.cloudfront`: one distribution
serving one existing private S3 bucket, no custom domain, no WAF. Every
other input keeps the module's defaults: `PriceClass_100`, `index.html` as
the default root object, the `CachingOptimized` managed cache policy, and
the CloudFront default `*.cloudfront.net` certificate (since `aliases` is
empty, `viewer_certificate_arn` must stay unset).

This example does not create the origin bucket; `bucket_name` and
`bucket_regional_domain_name` are variables with no default, expected to
come from a bucket you already own (for example `aws.modules.s3`'s own
`aws_s3_bucket.this.bucket` and `.bucket_regional_domain_name` outputs). The
module never reaches into that bucket itself: `required_bucket_policy_json`
is the statement you still need to merge into the bucket's own policy before
the distribution can actually read anything from it. See the root
[README's Quick start](../../README.md#quick-start) for the full two-module
wiring, including that merge step.

## Run

```sh
terraform init
terraform plan \
  -var bucket_name=my-static-site-origin \
  -var bucket_regional_domain_name=my-static-site-origin.s3.us-east-1.amazonaws.com
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7.0, < 2.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.35.0, < 7.0.0 |

## Providers

No providers.

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_distribution"></a> [distribution](#module\_distribution) | ../../ | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_bucket_name"></a> [bucket\_name](#input\_bucket\_name) | Name of the existing private S3 bucket to serve, such as aws.modules.s3's aws\_s3\_bucket.this.bucket output. | `string` | n/a | yes |
| <a name="input_bucket_regional_domain_name"></a> [bucket\_regional\_domain\_name](#input\_bucket\_regional\_domain\_name) | Regional domain name of that bucket, such as aws.modules.s3's aws\_s3\_bucket.this.bucket\_regional\_domain\_name output. | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Human-readable identifier for the distribution: becomes its comment, the Origin Access Control's name, and the default Name tag. | `string` | `"static-site-minimal"` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region the distribution and its bucket-owning provider are configured against. CloudFront itself is global; this only affects which region Terraform's default provider talks to. | `string` | `"us-east-1"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_distribution_id"></a> [distribution\_id](#output\_distribution\_id) | ID of the distribution. |
| <a name="output_domain_name"></a> [domain\_name](#output\_domain\_name) | The distribution's own *.cloudfront.net domain name. |
| <a name="output_required_bucket_policy_json"></a> [required\_bucket\_policy\_json](#output\_required\_bucket\_policy\_json) | The bucket policy statement to merge into the origin bucket's own policy so the OAC can read it. |
<!-- END_TF_DOCS -->
