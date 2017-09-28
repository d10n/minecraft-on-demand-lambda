data "aws_region" "current" {
  current = true
}

terraform {
  backend "s3" {
    # bucket = "${var.aws_s3_terraform_state["value"]}"
    bucket         = "d10n-minecraft-terraform-state"    # terraform.backend: configuration cannot contain interpolations
    key            = "terraform.tfstate"
    dynamodb_table = "d10n-minecraft-terraform-dynamodb"

    # region = "${data.aws_region.current.name}"
    region = "us-east-1"
  }
}

resource "aws_vpc" "main" {
  cidr_block         = "10.0.0.0/16"
  enable_dns_support = true

  tags {
    Name = "Minecraft"
  }
}

resource "aws_subnet" "main" {
  tags {
    Name = "Minecraft"
  }

  vpc_id                  = "${aws_vpc.main.id}"
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
}

resource "aws_internet_gateway" "gw" {
  vpc_id = "${aws_vpc.main.id}"

  tags {
    Name = "Minecraft"
  }
}

resource "aws_route_table" "r" {
  vpc_id = "${aws_vpc.main.id}"

  tags {
    Name = "Minecraft"
  }

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.gw.id}"
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = "${aws_subnet.main.id}"
  route_table_id = "${aws_route_table.r.id}"
}

resource "aws_security_group" "allow_all" {
  vpc_id      = "${aws_vpc.main.id}"
  name        = "allow_all"
  description = "Allow all inbound traffic"

  ingress {
    from_port   = 25565
    to_port     = 25565
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Uncomment to open traffic to Dynmap plugin
  #  ingress {
  #    from_port   = 8123
  #    to_port     = 8123
  #    protocol    = "tcp"
  #    cidr_blocks = ["0.0.0.0/0"]
  #  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  # "137112412989" is also Amazon
  # "099720109477" is Canonical

  # filter {
  #   name = "owner-alias"
  #   values = ["ubuntu"]
  # }
  filter {
    name   = "name"
    values = ["amzn-ami-hvm-2017.03*-x86_64-gp2"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]               # better performance than paravirtual
  }
}

resource "aws_iam_instance_profile" "minecraft_s3" {
  name = "minecraft_s3_instance_profile"
  role = "${aws_iam_role.s3_role.name}"
}

resource "aws_iam_role_policy" "s3_policy" {
  name = "minecraft_s3_policy"
  role = "${aws_iam_role.s3_role.id}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:*",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_role" "s3_role" {
  name = "minecraft_s3_role"
  path = "/"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

data "template_file" "provision_minecraft" {
  template = "${file("provision_minecraft.sh")}"

  vars = {
    aws_s3_world_backup = "${var.aws_s3_world_backup["value"]}"
  }
}

resource "aws_instance" "minecraft" {
  # ami = "ami-b374d5a5"
  ami                    = "${data.aws_ami.amazon_linux.id}"
  instance_type          = "t2.micro"
  vpc_security_group_ids = ["${aws_security_group.allow_all.id}"]

  tags {
    Name = "Minecraft"
  }

  depends_on = ["aws_internet_gateway.gw"]
  subnet_id  = "${aws_subnet.main.id}"

  # depends_on = [
  #   "aws_s3_bucket.minecraft_terraform_plan",
  #   "aws_s3_bucket.minecraft_world_backup"]
  key_name = "${var.aws_key_pair["value"]}" # "${aws_key_pair.terraform_minecraft.id}"

  # provisioner "local-exec" {
  #   command = "echo ${aws_instance.minecraft.public_ip} > ip_address.txt"
  # }
  iam_instance_profile = "${aws_iam_instance_profile.minecraft_s3.id}"

  user_data = "${data.template_file.provision_minecraft.rendered}"
}

resource "aws_eip_association" "eip_association" {
  # allocation_id = "eipalloc-50076862"
  allocation_id = "${var.aws_eip_id["value"]}"
  instance_id   = "${aws_instance.minecraft.id}"
}

# vim: ts=2 sw=2 et

