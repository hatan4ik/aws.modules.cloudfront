# Sibling statement-type fixture

Used by `tests/policy_statement_bridge.tftest.hcl` to prove that the module's
`required_bucket_policy_statement` and `required_kms_key_policy_statement`
outputs can be passed, unchanged (and merged with other statements), into
`aws.modules.s3`'s `bucket_policy_statements` and `aws.modules.kms`'s
`policy_statements` inputs. It declares literal copies of those two input
types and echoes the converted values back so the test can assert on them
after Terraform's type conversion and optional-attribute defaults.

It creates nothing and declares no provider. It is test scaffolding, not a
deployable pattern. If either sibling module changes its statement type, update
the copy here and re-run `make test`.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7.0, < 2.0.0 |

## Providers

No providers.

## Modules

No modules.

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_kms_policy_statements"></a> [kms\_policy\_statements](#input\_kms\_policy\_statements) | Literal copy of the type of aws.modules.kms's policy\_statements input (modules/key-policy's statements; unchanged since v1.0.0). Assigning the module's required\_kms\_key\_policy\_statement output here proves it converts to that type with no translation. | <pre>map(object({<br/>    effect     = optional(string, "Allow")<br/>    principals = map(set(string))<br/>    actions    = set(string)<br/>    resources  = optional(set(string), ["*"])<br/>    conditions = optional(list(object({<br/>      test     = string<br/>      variable = string<br/>      values   = set(string)<br/>    })), [])<br/>  }))</pre> | `{}` | no |
| <a name="input_s3_bucket_policy_statements"></a> [s3\_bucket\_policy\_statements](#input\_s3\_bucket\_policy\_statements) | Literal copy of the type of aws.modules.s3's bucket\_policy\_statements input (variables.tf; unchanged from v1.0.0 through v1.0.1). Assigning the module's required\_bucket\_policy\_statement output here proves it converts to that type with no translation. | <pre>map(object({<br/>    effect        = optional(string, "Allow")<br/>    principals    = optional(map(set(string)), {})<br/>    principal_all = optional(bool, false)<br/>    actions       = set(string)<br/>    resources     = optional(set(string))<br/>    conditions = optional(list(object({<br/>      test     = string<br/>      variable = string<br/>      values   = set(string)<br/>    })), [])<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_kms_policy_statements"></a> [kms\_policy\_statements](#output\_kms\_policy\_statements) | kms\_policy\_statements after conversion to aws.modules.kms's type, optional defaults applied. |
| <a name="output_s3_bucket_policy_statements"></a> [s3\_bucket\_policy\_statements](#output\_s3\_bucket\_policy\_statements) | s3\_bucket\_policy\_statements after conversion to aws.modules.s3's type, optional defaults applied. |
<!-- END_TF_DOCS -->
