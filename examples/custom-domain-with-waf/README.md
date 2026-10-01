# Custom domain with WAF

A distribution for a custom domain, protected by a global WAF Web ACL, per
[ADR 0004](/docs/adr/0004-edge-ingress-and-egress.md)'s "WAF at every entry
layer." This example shows the `us-east-1` constraint end to end: both
`viewer_certificate_arn` and `web_acl_arn` must come from resources created
through a `us-east-1` provider (see `aws.modules.acm`'s `cloudfront` example
and `aws.modules.waf`'s own `us-east-1` alias requirement), which this
example only consumes as ARNs — it does not itself need a `us-east-1`
provider, since CloudFront resources are global.

Both ARNs' region segments are validated at plan time: the certificate's must
say `us-east-1`, and so must the Web ACL's. A real CLOUDFRONT-scope Web ACL
ARN looks like
`arn:aws:wafv2:us-east-1:<account>:global/webacl/<name>/<id>` (the region is
`us-east-1`; `global` only marks the scope in the resource segment), which is
exactly what `aws.modules.waf`'s `web_acl_arn` output returns for
`scope = "CLOUDFRONT"`. See [docs/DESIGN.md](../../docs/DESIGN.md).

Access logging is also turned on here, to a bucket separate from the origin
bucket, satisfying both of the module's advisory `check` blocks
(`access_logging_disabled`, `web_acl_not_attached`).

## Run

```sh
terraform init
terraform plan \
  -var bucket_name=my-static-site-origin \
  -var bucket_regional_domain_name=my-static-site-origin.s3.us-east-1.amazonaws.com \
  -var domain_name=app.example.com \
  -var viewer_certificate_arn=arn:aws:acm:us-east-1:123456789012:certificate/11111111-2222-3333-4444-555555555555 \
  -var web_acl_arn=arn:aws:wafv2:us-east-1:123456789012:global/webacl/app-example-com/11111111-1111-1111-1111-111111111111 \
  -var access_log_bucket_domain_name=my-cloudfront-logs.s3.us-east-1.amazonaws.com
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
| <a name="input_access_log_bucket_domain_name"></a> [access\_log\_bucket\_domain\_name](#input\_access\_log\_bucket\_domain\_name) | Regional domain name of a separate, caller-owned S3 bucket that receives standard CloudFront access logs. Kept separate from the origin bucket on purpose: logs and served content have different retention and access needs. | `string` | n/a | yes |
| <a name="input_bucket_name"></a> [bucket\_name](#input\_bucket\_name) | Name of the existing private S3 bucket to serve. | `string` | n/a | yes |
| <a name="input_bucket_regional_domain_name"></a> [bucket\_regional\_domain\_name](#input\_bucket\_regional\_domain\_name) | Regional domain name of that bucket. | `string` | n/a | yes |
| <a name="input_domain_name"></a> [domain\_name](#input\_domain\_name) | Custom domain the distribution answers to, such as app.example.com. | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Human-readable identifier for the distribution. | `string` | `"static-site-custom-domain"` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region Terraform's default provider talks to. CloudFront itself is global; the certificate and Web ACL below must still have been created through a separate us-east-1 provider elsewhere, which this example only consumes ARNs from. | `string` | `"us-east-1"` | no |
| <a name="input_viewer_certificate_arn"></a> [viewer\_certificate\_arn](#input\_viewer\_certificate\_arn) | ACM certificate ARN for domain\_name, requested through a us-east-1 provider (see aws.modules.acm's cloudfront example). Its region segment is validated by the module; that it was actually requested via us-east-1 is not something an ARN string can prove and is the caller's responsibility. | `string` | n/a | yes |
| <a name="input_web_acl_arn"></a> [web\_acl\_arn](#input\_web\_acl\_arn) | ARN of a CLOUDFRONT-scope WAFv2 Web ACL (aws.modules.waf's web\_acl\_arn output with scope = "CLOUDFRONT", created through us-east-1), such as arn:aws:wafv2:us-east-1:123456789012:global/webacl/app-example-com/<uuid>. The module validates both the us-east-1 region segment and the global/webacl/ resource segment. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_distribution_id"></a> [distribution\_id](#output\_distribution\_id) | ID of the distribution. |
| <a name="output_domain_name"></a> [domain\_name](#output\_domain\_name) | The distribution's own *.cloudfront.net domain name (the custom alias is a CNAME/ALIAS to it). |
| <a name="output_hosted_zone_id"></a> [hosted\_zone\_id](#output\_hosted\_zone\_id) | CloudFront's fixed alias-target hosted zone ID, for a Route 53 alias record pointing domain\_name at this distribution. |
| <a name="output_required_bucket_policy_json"></a> [required\_bucket\_policy\_json](#output\_required\_bucket\_policy\_json) | The bucket policy statement to merge into the origin bucket's own policy. |
<!-- END_TF_DOCS -->
