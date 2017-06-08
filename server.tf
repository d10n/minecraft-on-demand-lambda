provider "aws" {
  access_key = "{key}"
  secret_key = "{key}"
  region     = "us-east-1"
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

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "example" {
  ami             = "ami-c58c1dd3"
  instance_type   = "t2.micro"
  security_groups = ["${aws_security_group.allow_all.id}"]

  tags {
    Name = "Minecraft"
  }

  user_data            = "${file("minecraft.sh")}"
  key_name             = "Terraformkey"
  depends_on           = ["aws_internet_gateway.gw"]
  subnet_id            = "${aws_subnet.main.id}"
  iam_instance_profile = "s3"
}

resource "aws_eip_association" "eip_assoc" {
  instance_id   = "${aws_instance.example.id}"
  allocation_id = "eipalloc-94ce0aa4"
}
