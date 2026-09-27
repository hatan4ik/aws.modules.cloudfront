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
}
