# ── KMS Customer-Managed Key (CMK) ────────────────────────────────────────────
# FedRAMP controls: SC-28 (Protection of Information at Rest)
# NIST SP 800-57 requires key rotation and documented key lifecycle.
#
# This CMK encrypts the EBS root volume.
# A separate CMK for CloudWatch logs is a FedRAMP High step — add it when
# you're ready to go through a formal assessment.

resource "aws_kms_key" "ebs" {
  description             = "CMK for EBS volume encryption - lab-boinc-grafana"
  enable_key_rotation     = true # NIST SP 800-57 annual rotation
  deletion_window_in_days = 7

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Root account retains full administrative control (required)
        Sid    = "RootAdministration"
        Effect = "Allow"
        Principal = {
          AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        # EC2 service needs these to attach encrypted EBS at boot time
        Sid    = "EC2EBSEncryption"
        Effect = "Allow"
        Principal = {
          Service = "ec2.${data.aws_partition.current.dns_suffix}"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:CreateGrant",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:CallerAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })

  tags = { Name = "lab-ebs-cmk" }
}

resource "aws_kms_alias" "ebs" {
  name          = "alias/lab-ebs"
  target_key_id = aws_kms_key.ebs.key_id
}
