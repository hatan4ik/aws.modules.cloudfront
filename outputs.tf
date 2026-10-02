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

output "required_kms_key_policy_json" {
  description = "The KMS key-policy STATEMENT (not a full policy document) the origin bucket's encryption key needs when objects are encrypted with SSE-KMS (aws:kms or aws:kms:dsse) under a CUSTOMER MANAGED key, as a JSON string: grants cloudfront.amazonaws.com kms:Decrypt, scoped by Condition.StringEquals[\"AWS:SourceArn\"] to this distribution's own ARN. Add it (jsondecode it first) to that key's policy. Not needed for SSE-S3 (AES256). It cannot be used with the AWS managed aws/s3 key, whose key policy cannot be edited: OAC cannot read objects encrypted under aws/s3, so use a customer managed key or SSE-S3 instead (aws.modules.s3 defaults to aws:kms with aws/s3 when kms_key_arn is null). Without this statement CloudFront fails closed: every object request returns 403 AccessDenied."
  value       = jsonencode(local.kms_key_policy_statement)
}
