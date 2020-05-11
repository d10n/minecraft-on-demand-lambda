terraform {
  # Version of Terraform to include in the bundle. An exact version number
  # is required.
  version = "0.12.24"
}

# Define which provider plugins are to be included
providers {
  archive = ["~> 1.3"]
  aws = ["~> 2.61"]
  local = ["~> 1.4"]
  template = ["~> 2.1"]
}
