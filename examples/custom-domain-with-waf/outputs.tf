output "distribution_id" {
  description = "ID of the distribution."
  value       = module.distribution.distribution_id
}

output "domain_name" {
  description = "The distribution's own *.cloudfront.net domain name (the custom alias is a CNAME/ALIAS to it)."
  value       = module.distribution.domain_name
}

output "hosted_zone_id" {
  description = "CloudFront's fixed alias-target hosted zone ID, for a Route 53 alias record pointing domain_name at this distribution."
  value       = module.distribution.hosted_zone_id
}

output "required_bucket_policy_json" {
  description = "The bucket policy statement to merge into the origin bucket's own policy."
  value       = module.distribution.required_bucket_policy_json
}
