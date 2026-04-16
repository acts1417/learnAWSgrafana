# ── EC2 Instance Role ─────────────────────────────────────────────────────────
# FedRAMP control: AC-6 (Least Privilege)
# Custom inline policies grant only what this instance actually needs.
# No AWS-managed policies — they are intentionally broad and fail least-privilege.

resource "aws_iam_role" "lab_ec2" {
  name        = "lab-ec2-role"
  description = "EC2 role for lab-boinc-grafana - least privilege (FedRAMP AC-6)"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.${data.aws_partition.current.dns_suffix}" }
    }]
  })

  tags = { Name = "lab-ec2-role" }
}

# Minimum permissions for SSM Session Manager (browser/CLI shell without opening port 22)
# Ref: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-getting-started-instance-profile.html
resource "aws_iam_role_policy" "ssm_session" {
  name = "ssm-session-manager-minimal"
  role = aws_iam_role.lab_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SSMCoreChannels"
        Effect = "Allow"
        Action = [
          "ssm:UpdateInstanceInformation",
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      },
      {
        # SSM checks bucket encryption config when logging sessions to S3 (optional feature)
        Sid      = "SSMEncryptionCheck"
        Effect   = "Allow"
        Action   = ["s3:GetEncryptionConfiguration"]
        Resource = "*"
      }
    ]
  })
}

# Allow the instance to use the EBS CMK (needed for the OS to read/write the root volume)
resource "aws_iam_role_policy" "kms_ebs" {
  name = "kms-ebs-access"
  role = aws_iam_role.lab_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "UseEBSKey"
      Effect = "Allow"
      Action = [
        "kms:Decrypt",
        "kms:GenerateDataKey",
        "kms:DescribeKey"
      ]
      Resource = [aws_kms_key.ebs.arn]
    }]
  })
}

resource "aws_iam_instance_profile" "lab" {
  name = "lab-ec2-profile"
  role = aws_iam_role.lab_ec2.name
}

# ── VPC Flow Logs Role ────────────────────────────────────────────────────────
# Scoped to write only to the specific CloudWatch log group — not all of CloudWatch.

resource "aws_iam_role" "flow_logs" {
  name        = "lab-vpc-flow-logs-role"
  description = "Allows VPC Flow Logs to write to CloudWatch - least privilege"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "flow_logs_write" {
  name = "flow-logs-cloudwatch-write"
  role = aws_iam_role.flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "WriteFlowLogs"
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams"
      ]
      # Scoped to exactly our log group — not all of CloudWatch
      Resource = "${aws_cloudwatch_log_group.vpc_flow_logs.arn}:*"
    }]
  })
}
