# Disposable S3 origin bucket for the smoke suite in the parent directory.
#
# Unlike aws.modules.s3's own integration fixture (which creates no AWS
# resource, because the module under test creates its bucket itself),
# aws.modules.cloudfront never creates or reaches into its origin bucket - see
# docs/DESIGN.md. So this fixture creates the bucket itself, plainly, not
# through aws.modules.s3, to keep it minimal: just enough to give the module
# under test a real, private bucket to serve. A random suffix keeps concurrent
# runs from colliding on the global S3 bucket namespace.

resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  bucket_name = "${var.name_prefix}-${random_id.suffix.hex}"
  probe_body  = "aws.modules.cloudfront integration probe ${random_id.suffix.hex}"

  tags = merge(var.tags, {
    IntegrationTest = "aws.modules.cloudfront"
    Disposable      = "true"
  })
}

resource "aws_s3_bucket" "origin" {
  bucket        = local.bucket_name
  force_destroy = true
  tags          = local.tags
}

# BucketOwnerEnforced disables ACLs entirely, and every public access block
# stays on: OAC reads through a bucket policy scoped to the distribution's own
# SourceArn, which S3's public access block logic does not treat as public
# (the principal is the cloudfront.amazonaws.com service, not "*"), so there is
# no need to relax any of the four blocks for the smoke suite to attach that
# policy.
resource "aws_s3_bucket_public_access_block" "origin" {
  bucket = aws_s3_bucket.origin.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "origin" {
  bucket = aws_s3_bucket.origin.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# One known object for the smoke suite to fetch through the distribution, so
# it can prove the OAC read path end to end: denied (403) before the module's
# required_bucket_policy_json is attached, served (200, this exact body)
# after. SSE-S3 (the S3 default for a new bucket), so no KMS key policy is
# involved; see the README's "SSE-KMS origins" section for that case.
resource "aws_s3_object" "probe" {
  bucket       = aws_s3_bucket.origin.id
  key          = "index.html"
  content      = local.probe_body
  content_type = "text/html"

  depends_on = [aws_s3_bucket_ownership_controls.origin]
}
