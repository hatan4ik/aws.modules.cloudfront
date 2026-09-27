output "distribution_id" {
  description = "ID of the distribution."
  value       = aws_cloudfront_distribution.this.id
}

output "distribution_arn" {
  description = "ARN of the distribution. Also the value scoped into required_bucket_policy_json's AWS:SourceArn condition."
  value       = aws_cloudfront_distribution.this.arn
}

output "domain_name" {
  description = "Distribution's own *.cloudfront.net domain name. Use this, or a custom alias, as the target of a DNS record."
  value       = aws_cloudfront_distribution.this.domain_name
}

output "hosted_zone_id" {
  description = "CloudFront's fixed alias-target hosted zone ID (Z2FDTNDATAQYW2 in the standard aws partition), for a Route 53 alias record via aws.modules.route53. It identifies CloudFront as an alias target class, not a zone this distribution owns."
  value       = local.cloudfront_hosted_zone_id
}

output "origin_access_control_id" {
  description = "ID of the Origin Access Control this distribution reads the S3 origin through."
  value       = aws_cloudfront_origin_access_control.this.id
}

output "required_bucket_policy_json" {
  description = "The exact IAM policy STATEMENT (not a full policy document) the origin bucket needs, as a JSON string: grants cloudfront.amazonaws.com s3:GetObject on the origin path, scoped by a Condition.StringEquals[\"AWS:SourceArn\"] to this distribution's own ARN. Merge it (jsondecode it first) into a standalone aws_s3_bucket_policy's statement list, or translate it into aws.modules.s3's own typed bucket_policy_statements input (its principals and conditions fields have a different shape than raw IAM JSON); this module cannot attach it itself because it does not own the bucket. A missing or wrong SourceArn here would let any CloudFront distribution in the account read the bucket, not just this one."
  value       = jsonencode(local.bucket_policy_statement)
}
