provider "aws" {
  access_key = "{key}"
  secret_key = "{key}"
  region     = "us-east-1"
}

resource "aws_security_group" "allow_all" {
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

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "example" {
  ami           = "ami-c58c1dd3"
  instance_type = "t2.micro"
  security_groups = ["${aws_security_group.allow_all.name}"]
  tags {
    Name = "Minecraft"
  }
  user_data = "${file("minecraft.sh")}",
  key_name = "Terraformkey",
  iam_instance_profile = "s3"
}
