# Lambda Functions and IAM Role for SD-WAN Orchestration
# Deploys Phase1, Phase2, Phase3 Lambda functions with shared code from lambda/

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {
  provider = aws.virginia
}

data "archive_file" "lambda_package" {
  type        = "zip"
  source_dir  = "${path.module}/${var.lambda_source_dir}"
  output_path = "${path.module}/.build/lambda.zip"

  excludes = [
    "__pycache__",
    "*.pyc",
  ]
}

# -----------------------------------------------------------------------------
# IAM Role for Lambda Execution
# -----------------------------------------------------------------------------

resource "aws_iam_role" "sdwan_lambda_execution_role" {
  provider = aws.virginia
  name     = "sdwan-lambda-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "sdwan-lambda-execution-role"
  }
}

resource "aws_iam_role_policy" "sdwan_lambda_policy" {
  provider = aws.virginia
  name     = "sdwan-lambda-policy"
  role     = aws_iam_role.sdwan_lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SSMSendCommand"
        Effect = "Allow"
        Action = "ssm:SendCommand"
        Resource = [
          "arn:aws:ssm:*:*:document/AWS-RunShellScript",
          aws_instance.nv_sdwan_sdwan_instance.arn,
          aws_instance.nv_branch1_sdwan_instance.arn,
          aws_instance.fra_sdwan_sdwan_instance.arn,
          aws_instance.fra_branch1_sdwan_instance.arn,
        ]
      },
      {
        Sid    = "SSMCommandInvocation"
        Effect = "Allow"
        Action = [
          "ssm:GetCommandInvocation",
          "ssm:DescribeInstanceInformation",
        ]
        Resource = "*"
      },
      {
        Sid      = "SSMGetParameter"
        Effect   = "Allow"
        Action   = "ssm:GetParameter"
        Resource = "arn:aws:ssm:*:${data.aws_caller_identity.current.account_id}:parameter/sdwan/*"
      },
      {
        Sid      = "SSMGetParametersByPath"
        Effect   = "Allow"
        Action   = "ssm:GetParametersByPath"
        Resource = [
          "arn:aws:ssm:*:${data.aws_caller_identity.current.account_id}:parameter/sdwan",
          "arn:aws:ssm:*:${data.aws_caller_identity.current.account_id}:parameter/sdwan/",
        ]
      },
      {
        Sid      = "SSMPutParameter"
        Effect   = "Allow"
        Action   = "ssm:PutParameter"
        Resource = "arn:aws:ssm:*:${data.aws_caller_identity.current.account_id}:parameter/sdwan/*"
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:aws:logs:*:${data.aws_caller_identity.current.account_id}:*"
      },
    ]
  })
}

# -----------------------------------------------------------------------------
# Lambda Functions
# -----------------------------------------------------------------------------

resource "aws_lambda_function" "sdwan_phase1" {
  provider         = aws.virginia
  function_name    = "sdwan-phase1"
  description      = "SD-WAN Phase 1 - Base setup: packages, LXD, VyOS container"
  role             = aws_iam_role.sdwan_lambda_execution_role.arn
  handler          = "phase1_handler.handler"
  runtime          = "python3.12"
  timeout          = 900
  memory_size      = 256
  filename         = data.archive_file.lambda_package.output_path
  source_code_hash = data.archive_file.lambda_package.output_base64sha256

  environment {
    variables = {
      SSM_PARAM_PREFIX = "/sdwan/"
    }
  }

  tags = {
    Name  = "sdwan-phase1"
    Phase = "1-base-setup"
  }
}

resource "aws_lambda_function" "sdwan_phase2" {
  provider         = aws.virginia
  function_name    = "sdwan-phase2"
  description      = "SD-WAN Phase 2 - VPN/BGP configuration"
  role             = aws_iam_role.sdwan_lambda_execution_role.arn
  handler          = "phase2_handler.handler"
  runtime          = "python3.12"
  timeout          = 600
  memory_size      = 256
  filename         = data.archive_file.lambda_package.output_path
  source_code_hash = data.archive_file.lambda_package.output_base64sha256

  environment {
    variables = {
      SSM_PARAM_PREFIX = "/sdwan/"
    }
  }

  tags = {
    Name  = "sdwan-phase2"
    Phase = "2-vpn-bgp-config"
  }
}

resource "aws_lambda_function" "sdwan_phase3" {
  provider         = aws.virginia
  function_name    = "sdwan-phase3"
  description      = "SD-WAN Phase 3 - Cloud WAN BGP configuration"
  role             = aws_iam_role.sdwan_lambda_execution_role.arn
  handler          = "phase3_handler.handler"
  runtime          = "python3.12"
  timeout          = 600
  memory_size      = 256
  filename         = data.archive_file.lambda_package.output_path
  source_code_hash = data.archive_file.lambda_package.output_base64sha256

  environment {
    variables = {
      SSM_PARAM_PREFIX = "/sdwan/"
    }
  }

  tags = {
    Name  = "sdwan-phase3"
    Phase = "3-cloudwan-bgp"
  }
}

resource "aws_lambda_function" "sdwan_phase4" {
  provider         = aws.virginia
  function_name    = "sdwan-phase4"
  description      = "SD-WAN Phase 4 - Verification: IPsec, BGP, Cloud WAN BGP, connectivity"
  role             = aws_iam_role.sdwan_lambda_execution_role.arn
  handler          = "phase4_handler.handler"
  runtime          = "python3.12"
  timeout          = 600
  memory_size      = 256
  filename         = data.archive_file.lambda_package.output_path
  source_code_hash = data.archive_file.lambda_package.output_base64sha256

  environment {
    variables = {
      SSM_PARAM_PREFIX = "/sdwan/"
    }
  }

  tags = {
    Name  = "sdwan-phase4"
    Phase = "4-verify"
  }
}
