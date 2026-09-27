output "distribution_id" {
  description = "ID of the distribution."
  value       = module.distribution.distribution_id
}

output "domain_name" {
  description = "The distribution's own *.cloudfront.net domain name."
  value       = module.distribution.domain_name
}

output "required_bucket_policy_json" {
  description = "The bucket policy statement to merge into the origin bucket's own policy so the OAC can read it."
  value       = module.distribution.required_bucket_policy_json
}
