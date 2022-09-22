remote_state {
  backend = "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    bucket  = "${local.bucket}"
    region  = "${local.region}"
    encrypt = true
    key     = "${local.cluster_name}/${path_relative_to_include()}/terraform.tfstate"
  }
}

# Indicate what region to deploy the resources into
generate "provider" {
  path = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents = <<EOF
provider "aws" {
  region = "${local.region}"
}
EOF
}

locals {
   tags = {
    name      = "test"
    env       = "staging"
    terraform = true
  }

  customer_vars = yamldecode(file(get_env("OBMONDO_VARS_FILE")))

  cluster_name = local.customer_vars.cluster_name
  subdomain    = "${local.customer_vars.environment}.${local.customer_vars.domain_name}"
  region       = local.customer_vars.region
  bucket       = local.customer_vars.terraform_bucket
}
