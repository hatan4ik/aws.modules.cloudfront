locals {
  # The caller's Name tag wins; the module only fills the gap.
  tags = merge({ Name = var.name }, var.tags)

  partition = var.partition != null ? var.partition : data.aws_partition.current[0].partition

  # CloudFront's alias-target hosted zone ID is fixed for every distribution
  # in the standard aws partition (documented by AWS, not looked up); see
  # docs/DESIGN.md. It is not the ID of a zone this module owns or creates.
  cloudfront_hosted_zone_id = "Z2FDTNDATAQYW2"

  # AWS managed cache policy "CachingOptimized" (max TTL 1 year, gzip/br
  # compression negotiated), the sane default for static content.
  caching_optimized_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"

  has_aliases = length(var.aliases) > 0

  default_cache_behavior = {
    allowed_methods = var.default_cache_behavior.allowed_methods
    cached_methods  = var.default_cache_behavior.cached_methods
    cache_policy_id = coalesce(var.default_cache_behavior.cache_policy_id, local.caching_optimized_policy_id)
    compress        = var.default_cache_behavior.compress
  }

  # A list, not a map: CloudFront matches the first ordered behavior whose
  # path_pattern matches, so the caller's list order is the precedence order
  # and must reach the dynamic block unchanged (a map would iterate in
  # lexical key order instead).
  cache_behaviors = [
    for behavior in var.cache_behaviors : {
      path_pattern    = behavior.path_pattern
      allowed_methods = behavior.allowed_methods
      cached_methods  = behavior.cached_methods
      cache_policy_id = coalesce(behavior.cache_policy_id, local.caching_optimized_policy_id)
      compress        = behavior.compress
    }
  ]

  # The bucket-side statement the caller must merge into the origin bucket's
  # policy (aws.modules.s3's additional_bucket_policy_statements, or a plain
  # aws_s3_bucket_policy). Scoped to this distribution's own ARN so no other
  # distribution in the account can read the bucket through the same OAC
  # service principal; see docs/DESIGN.md for why AWS:SourceArn is required.
  bucket_resource_prefix = var.origin.origin_path == "" ? "" : var.origin.origin_path

  bucket_policy_statement = {
    Sid       = "AllowCloudFrontServicePrincipalReadOnly"
    Effect    = "Allow"
    Principal = { Service = "cloudfront.amazonaws.com" }
    Action    = "s3:GetObject"
    Resource  = "arn:${local.partition}:s3:::${var.origin.bucket_name}${local.bucket_resource_prefix}/*"
    Condition = {
      StringEquals = {
        "AWS:SourceArn" = aws_cloudfront_distribution.this.arn
      }
    }
  }
}
