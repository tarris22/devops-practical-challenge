terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_ssm_parameter" "ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  common_tags = {
    Project   = var.project_name
    ManagedBy = "Terraform"
  }
}

resource "aws_security_group" "app" {
  name_prefix = "${var.project_name}-"
  description = "Allow HTTP access to the demo application"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP application traffic"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Outbound traffic for package and application downloads"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}

resource "aws_instance" "app" {
  ami                         = data.aws_ssm_parameter.ami.value
  instance_type               = "t3.micro"
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.app.id]
  associate_public_ip_address = true

  user_data = <<-USERDATA
    #!/bin/bash
    set -euxo pipefail
    dnf install -y docker git
    systemctl enable --now docker

    git clone --depth 1 --branch main \
      https://github.com/tarris22/devops-practical-challenge.git \
      /opt/devops-practical-challenge

    cd /opt/devops-practical-challenge
    docker build -t devops-practical-challenge:latest .
    docker run -d \
      --name devops-practical-challenge \
      --restart unless-stopped \
      -p 80:5000 \
      devops-practical-challenge:latest
  USERDATA

  root_block_device {
    volume_size           = 8
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  metadata_options {
    http_tokens = "required"
  }

  tags = local.common_tags
}

output "instance_id" {
  value = aws_instance.app.id
}

output "public_ip" {
  value = aws_instance.app.public_ip
}

output "application_url" {
  value = "http://${aws_instance.app.public_ip}"
}
