# Step Functions State Machine and IAM Role for SD-WAN Orchestration
# Orchestrates Phase1 → Wait → Phase2 → Wait → Phase3 (Cloud WAN BGP) → Wait → Phase4 (Verify)

# -----------------------------------------------------------------------------
# IAM Role for Step Functions Execution
# -----------------------------------------------------------------------------

resource "aws_iam_role" "sdwan_stepfunctions_role" {
  provider = aws.virginia
  name     = "sdwan-stepfunctions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "sdwan-stepfunctions-role"
  }
}

resource "aws_iam_role_policy" "sdwan_stepfunctions_policy" {
  provider = aws.virginia
  name     = "sdwan-stepfunctions-policy"
  role     = aws_iam_role.sdwan_stepfunctions_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "InvokeLambda"
        Effect = "Allow"
        Action = "lambda:InvokeFunction"
        Resource = [
          aws_lambda_function.sdwan_phase1.arn,
          aws_lambda_function.sdwan_phase2.arn,
          aws_lambda_function.sdwan_phase3.arn,
          aws_lambda_function.sdwan_phase4.arn,
        ]
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies",
          "logs:DescribeLogGroups",
        ]
        Resource = "*"
      },
    ]
  })
}

# -----------------------------------------------------------------------------
# CloudWatch Log Group for Step Functions
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "sdwan_stepfunctions" {
  provider          = aws.virginia
  name              = "/aws/vendedlogs/states/sdwan-orchestration"
  retention_in_days = 30

  tags = {
    Name = "sdwan-stepfunctions-logs"
  }
}

# -----------------------------------------------------------------------------
# Step Functions State Machine
# -----------------------------------------------------------------------------

resource "aws_sfn_state_machine" "sdwan_orchestration" {
  provider = aws.virginia
  name     = "sdwan-orchestration"
  role_arn = aws_iam_role.sdwan_stepfunctions_role.arn

  definition = jsonencode({
    Comment = "SD-WAN Configuration Orchestration"
    StartAt = "Phase1_BaseSetup"
    States = {
      Phase1_BaseSetup = {
        Type     = "Task"
        Resource = aws_lambda_function.sdwan_phase1.arn
        Retry = [
          {
            ErrorEquals     = ["Lambda.ServiceException", "Lambda.AWSLambdaException", "Lambda.SdkClientException"]
            IntervalSeconds = 30
            MaxAttempts     = 2
            BackoffRate     = 2.0
          }
        ]
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "FailureState"
            ResultPath  = "$.error"
          }
        ]
        ResultPath = "$.phase1_result"
        Next       = "Wait_After_Phase1"
      }

      Wait_After_Phase1 = {
        Type    = "Wait"
        Seconds = var.phase1_wait_seconds
        Next    = "Phase2_VpnBgpConfig"
      }

      Phase2_VpnBgpConfig = {
        Type     = "Task"
        Resource = aws_lambda_function.sdwan_phase2.arn
        Retry = [
          {
            ErrorEquals     = ["Lambda.ServiceException", "Lambda.AWSLambdaException", "Lambda.SdkClientException"]
            IntervalSeconds = 30
            MaxAttempts     = 2
            BackoffRate     = 2.0
          }
        ]
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "FailureState"
            ResultPath  = "$.error"
          }
        ]
        ResultPath = "$.phase2_result"
        Next       = "Wait_After_Phase2"
      }

      Wait_After_Phase2 = {
        Type    = "Wait"
        Seconds = var.phase2_wait_seconds
        Next    = "Phase3_CloudWanBgp"
      }

      Phase3_CloudWanBgp = {
        Type     = "Task"
        Resource = aws_lambda_function.sdwan_phase3.arn
        Retry = [
          {
            ErrorEquals     = ["Lambda.ServiceException", "Lambda.AWSLambdaException", "Lambda.SdkClientException"]
            IntervalSeconds = 30
            MaxAttempts     = 2
            BackoffRate     = 2.0
          }
        ]
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "FailureState"
            ResultPath  = "$.error"
          }
        ]
        ResultPath = "$.phase3_result"
        Next       = "Wait_After_Phase3"
      }

      Wait_After_Phase3 = {
        Type    = "Wait"
        Seconds = 30
        Next    = "Phase4_Verify"
      }

      Phase4_Verify = {
        Type     = "Task"
        Resource = aws_lambda_function.sdwan_phase4.arn
        Retry = [
          {
            ErrorEquals     = ["Lambda.ServiceException", "Lambda.AWSLambdaException", "Lambda.SdkClientException"]
            IntervalSeconds = 30
            MaxAttempts     = 2
            BackoffRate     = 2.0
          }
        ]
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "FailureState"
            ResultPath  = "$.error"
          }
        ]
        ResultPath = "$.phase4_result"
        Next       = "SuccessState"
      }

      SuccessState = {
        Type = "Succeed"
      }

      FailureState = {
        Type  = "Fail"
        Cause = "Phase execution failed"
        Error = "PhaseExecutionError"
      }
    }
  })

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.sdwan_stepfunctions.arn}:*"
    include_execution_data = true
    level                  = "ERROR"
  }

  tags = {
    Name = "sdwan-orchestration"
  }
}
