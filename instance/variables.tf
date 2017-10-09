variable "aws_eip_id" {
  type = "map"

  default = {
    value = ""
  }
}

variable "aws_key_pair" {
  type = "map"
}

variable "aws_s3_terraform_state" {
  type = "map"
}

variable "aws_s3_world_backup" {
  type = "map"
}
