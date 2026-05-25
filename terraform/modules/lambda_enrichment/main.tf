data "aws_iam_policy_document" "lambda_assume" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "enrichment" {
  name               = "honeycloud-enrichment-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy" "enrichment" {
  role   = aws_iam_role.enrichment.id
  policy = data.aws_iam_policy_document.enrichment_policy.json
}

data "aws_iam_policy_document" "enrichment_policy" {
  statement {
    effect    = "Allow"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:*:*:*"]
  }
  statement {
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [var.sns_topic_arn]
  }
}

resource "aws_lambda_function" "enrichment" {
  function_name    = "honeycloud-alert-enrichment"
  filename         = var.lambda_zip_path
  handler          = "handler.lambda_handler"
  runtime          = "python3.11"
  role             = aws_iam_role.enrichment.arn
  timeout          = 30
  memory_size      = 256
  source_code_hash = filebase64sha256(var.lambda_zip_path)

  environment {
    variables = {
      SNS_TOPIC_ARN     = var.sns_topic_arn
      ABUSEIPDB_API_KEY = var.abuseipdb_api_key
    }
  }
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${aws_lambda_function.enrichment.function_name}"
  retention_in_days = 30
}
