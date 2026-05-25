data "aws_vpc" "default" { default = true }

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "availabilityZone"
    values = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d", "us-east-1f"]
  }
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
  filter {
    name   = "state"
    values = ["available"]
  }
}

resource "aws_iam_role" "ssrf_ec2" {
  name               = "honeycloud-ssrf-honeypot-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role_policy" "ssrf_ec2" {
  role   = aws_iam_role.ssrf_ec2.id
  policy = data.aws_iam_policy_document.ssrf_ec2_policy.json
}

data "aws_iam_policy_document" "ssrf_ec2_policy" {
  statement {
    effect    = "Allow"
    actions   = ["events:PutEvents"]
    resources = ["*"]
  }
}

resource "aws_iam_instance_profile" "ssrf_ec2" {
  name = "honeycloud-ssrf-honeypot-profile"
  role = aws_iam_role.ssrf_ec2.name
}

resource "aws_security_group" "ssrf" {
  name        = "honeycloud-ssrf-honeypot-sg"
  description = "HTTP inbound for SSRF honeypot"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
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

resource "aws_instance" "ssrf_honeypot" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t3.micro"
  subnet_id                   = tolist(data.aws_subnets.default.ids)[0]
  vpc_security_group_ids      = [aws_security_group.ssrf.id]
  iam_instance_profile        = aws_iam_instance_profile.ssrf_ec2.name
  associate_public_ip_address = true

  user_data = base64encode(templatefile("${path.module}/user_data.sh.tpl", {
    flask_app  = file("${path.module}/imds_mock.py")
    aws_region = var.aws_region
  }))

  tags = {
    Name        = "internal-build-agent-01"
    Environment = "production"
    Team        = "platform"
    Project     = "honeycloud"
  }
}
