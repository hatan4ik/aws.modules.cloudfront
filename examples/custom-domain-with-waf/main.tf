provider "aws" {
  region = var.region
}

module "distribution" {
  source = "../../"

  name = var.name

  origin = {
    bucket_name                 = var.bucket_name
    bucket_regional_domain_name = var.bucket_regional_domain_name
  }

  aliases                  = [var.domain_name]
  viewer_certificate_arn   = var.viewer_certificate_arn
  minimum_protocol_version = "TLSv1.2_2021"

  web_acl_arn = var.web_acl_arn

  logging = {
    bucket_domain_name = var.access_log_bucket_domain_name
    prefix             = "cloudfront/${var.name}/"
  }
}
