# SPA with error rewrites

A distribution serving a single-page application's built assets from a
private S3 bucket, with `custom_error_responses` rewriting the origin's 403
and 404 (a route the client-side router owns, which does not exist as an S3
key) to `/index.html` with a `200`, so deep-linking into any client route
works. `default_cache_behavior` uses the AWS managed `CachingDisabled` policy
for the app shell so a new deployment is visible immediately, while an
`/static/*` cache behavior keeps the module's default `CachingOptimized`
policy for hashed, long-lived static assets.

This example does not create the origin bucket, does not set aliases or
`viewer_certificate_arn` (so the default `*.cloudfront.net` certificate is
used), and does not attach a WAF Web ACL, to keep the example focused on the
`custom_error_responses` and `cache_behaviors` shapes; see
[`examples/custom-domain-with-waf`](../custom-domain-with-waf) for those.

## Run

```sh
terraform init
terraform plan \
  -var bucket_name=my-spa-origin \
  -var bucket_regional_domain_name=my-spa-origin.s3.us-east-1.amazonaws.com
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
| <a name="input_bucket_name"></a> [bucket\_name](#input\_bucket\_name) | Name of the existing private S3 bucket holding the single-page application's built assets. | `string` | n/a | yes |
| <a name="input_bucket_regional_domain_name"></a> [bucket\_regional\_domain\_name](#input\_bucket\_regional\_domain\_name) | Regional domain name of that bucket. | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Human-readable identifier for the distribution. | `string` | `"spa-with-error-rewrites"` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region Terraform's default provider talks to. | `string` | `"us-east-1"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_distribution_id"></a> [distribution\_id](#output\_distribution\_id) | ID of the distribution. |
| <a name="output_domain_name"></a> [domain\_name](#output\_domain\_name) | The distribution's own *.cloudfront.net domain name. |
| <a name="output_required_bucket_policy_json"></a> [required\_bucket\_policy\_json](#output\_required\_bucket\_policy\_json) | The bucket policy statement to merge into the origin bucket's own policy. |
<!-- END_TF_DOCS -->
