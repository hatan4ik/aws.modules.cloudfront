# Literal copies of the sibling modules' statement input types. Keep them
# byte-for-byte in sync with the sources named in each description: the
# bridge test is only as strong as these copies are faithful.

variable "s3_bucket_policy_statements" {
  description = "Literal copy of the type of aws.modules.s3's bucket_policy_statements input (variables.tf; unchanged from v1.0.0 through v1.0.1). Assigning the module's required_bucket_policy_statement output here proves it converts to that type with no translation."
  type = map(object({
    effect        = optional(string, "Allow")
    principals    = optional(map(set(string)), {})
    principal_all = optional(bool, false)
    actions       = set(string)
    resources     = optional(set(string))
    conditions = optional(list(object({
      test     = string
      variable = string
      values   = set(string)
    })), [])
  }))
  default  = {}
  nullable = false
}

variable "kms_policy_statements" {
  description = "Literal copy of the type of aws.modules.kms's policy_statements input (modules/key-policy's statements; unchanged since v1.0.0). Assigning the module's required_kms_key_policy_statement output here proves it converts to that type with no translation."
  type = map(object({
    effect     = optional(string, "Allow")
    principals = map(set(string))
    actions    = set(string)
    resources  = optional(set(string), ["*"])
    conditions = optional(list(object({
      test     = string
      variable = string
      values   = set(string)
    })), [])
  }))
  default  = {}
  nullable = false
}
