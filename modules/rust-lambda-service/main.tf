# rust-lambda-service
#
# The Lambda + IAM execution role + log group + public Function URL stack that
# loom, model-gateway, granite, drive, pigeon, and bowerbird all copy-pasted.
# Public invocation is granted by a single native aws_lambda_permission with
# function_url_auth_type = "NONE" (supported since AWS provider 4.x); the old
# AccessDeniedException CloudFormation workaround is no longer needed.
#
# Service-specific resources (DynamoDB tables, S3 buckets, KMS keys, SNS
# topics, API Gateway, CloudFront) stay in each service's own config and are
# wired in through `env` and `extra_policy_statements`.

locals {
  lambda_name    = var.app_name
  log_group_name = "/aws/lambda/${local.lambda_name}"

  common_tags = merge({
    Project = var.app_name
    Service = coalesce(var.service, var.app_name)
    Managed = "terraform"
  }, var.tags)

  # Base CloudWatch Logs statements every service needs, plus whatever the
  # caller passes for its own resources.
  base_log_statements = [
    {
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Effect   = "Allow"
      Resource = "arn:aws:logs:${var.aws_region}:*:log-group:${local.log_group_name}:*"
    },
    {
      Action   = ["logs:CreateLogGroup"]
      Effect   = "Allow"
      Resource = "arn:aws:logs:${var.aws_region}:*:log-group:*"
    }
  ]

  policy_statements = concat(local.base_log_statements, var.extra_policy_statements)
}

resource "aws_iam_role" "lambda" {
  name = "${var.app_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "lambda" {
  name = "${var.app_name}-lambda-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = local.policy_statements
  })
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = local.log_group_name
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

resource "aws_lambda_function" "this" {
  function_name                  = local.lambda_name
  role                           = aws_iam_role.lambda.arn
  runtime                        = "provided.al2023"
  handler                        = "bootstrap"
  architectures                  = ["x86_64"]
  filename                       = var.zip_path
  source_code_hash               = filebase64sha256(var.zip_path)
  memory_size                    = var.lambda_memory_size
  timeout                        = var.lambda_timeout_seconds
  reserved_concurrent_executions = var.lambda_reserved_concurrency

  environment {
    variables = var.env
  }

  depends_on = [aws_cloudwatch_log_group.lambda]

  tags = local.common_tags
}

resource "aws_lambda_function_url" "this" {
  function_name      = aws_lambda_function.this.function_name
  authorization_type = "NONE"

  dynamic "cors" {
    for_each = var.function_url_cors == null ? [] : [var.function_url_cors]
    content {
      allow_origins  = cors.value.allow_origins
      allow_methods  = cors.value.allow_methods
      allow_headers  = cors.value.allow_headers
      expose_headers = cors.value.expose_headers
      max_age        = cors.value.max_age
    }
  }
}

resource "aws_lambda_permission" "function_url_public" {
  statement_id           = "AllowPublicFunctionUrlInvoke"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.this.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}
