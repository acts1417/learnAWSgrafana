locals {
  account_id = "569255103491"
  region     = "us-east-1"
}

# ── Lambda execution role ─────────────────────────────────────────────────────

resource "aws_iam_role" "start_ec2_lambda" {
  name = "lab-start-ec2-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "start_ec2_lambda" {
  name = "lab-start-ec2-lambda-policy"
  role = aws_iam_role.start_ec2_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ec2:StartInstances", "ec2:DescribeInstances"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# ── Lambda function ───────────────────────────────────────────────────────────

data "archive_file" "start_ec2" {
  type        = "zip"
  source_file = "${path.module}/lambda/start_ec2.py"
  output_path = "${path.module}/lambda/start_ec2.zip"
}

resource "aws_lambda_function" "start_ec2" {
  function_name    = "lab-start-ec2"
  role             = aws_iam_role.start_ec2_lambda.arn
  handler          = "start_ec2.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.start_ec2.output_path
  source_code_hash = data.archive_file.start_ec2.output_base64sha256
  timeout          = 30

  description = "Starts EC2 instances tagged auto-schedule=true each weekday morning"
}

# ── Allow EventBridge to invoke the Lambda ────────────────────────────────────

resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.start_ec2.function_name
  principal     = "events.amazonaws.com"
  source_arn    = "arn:aws:events:${local.region}:${local.account_id}:rule/morning-start-lab"
}

# ── Wire EventBridge rule to Lambda ──────────────────────────────────────────

resource "aws_cloudwatch_event_target" "morning_start" {
  rule      = "morning-start-lab"
  target_id = "StartLabEC2"
  arn       = aws_lambda_function.start_ec2.arn
}
