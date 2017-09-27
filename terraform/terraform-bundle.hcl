terraform {
  # Version of Terraform to include in the bundle. An exact version number
  # is required.
  version = "0.10.6"
}

# Define which provider plugins are to be included
providers {
  archive = ["~> 1.0"]
  aws = ["~> 0.1"]
  local = ["~> 1.0"]
  template = ["~> 0.1"]
}
