terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ── Provider ──────────────────────────────────────────────────────────────────
# Credentials come from env vars (AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY)
# or ~/.aws/credentials.  Never put secrets in .tf files.
#
# GovCloud: change region to us-gov-east-1 or us-gov-west-1 and point your
# credentials at the GovCloud partition — no other code changes are needed
# because all ARNs use data.aws_partition.current.partition below.
provider "aws" {
  region = var.aws_region
}

# ── Partition / account data ──────────────────────────────────────────────────
# aws_partition resolves to "aws" in commercial, "aws-us-gov" in GovCloud.
# Using it everywhere makes ARNs correct in both partitions without code changes.
data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ── VPC ──────────────────────────────────────────────────────────────────────

resource "aws_vpc" "lab" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = "lab-vpc" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true
  tags                    = { Name = "lab-public" }
}

resource "aws_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id
  tags   = { Name = "lab-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.lab.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lab.id
  }
  tags = { Name = "lab-public-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ── VPC Flow Logs ─────────────────────────────────────────────────────────────
# FedRAMP controls: AU-2 (Auditable Events), AU-12 (Audit Generation), SI-4 (Monitoring)
# Captures ALL traffic (ACCEPT + REJECT) to enable anomaly detection.

resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/aws/vpc/lab-flow-logs"
  retention_in_days = 90 # NIST SP 800-53 AU-11 minimum retention
  tags              = { Name = "lab-vpc-flow-logs" }
}

resource "aws_flow_log" "lab" {
  vpc_id          = aws_vpc.lab.id
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.flow_logs.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_logs.arn
  tags            = { Name = "lab-flow-log" }
}

# ── AMI — AWS Deep Learning Base (Ubuntu 22.04, NVIDIA drivers pre-installed) ─

data "aws_ami" "dlami" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Deep Learning Base OSS Nvidia Driver GPU AMI (Ubuntu 22.04)*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}
