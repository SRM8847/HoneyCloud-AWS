# Rule 1: any API call by the canary IAM user
resource "aws_cloudwatch_event_rule" "canary_iam" {
  name        = "honeycloud-canary-iam-trigger"
  description = "Fires on any API call by the canary IAM user"

  event_pattern = jsonencode({
    source        = ["aws.sts", "aws.iam", "aws.s3", "aws.ec2", "aws.lambda"]
    "detail-type" = ["AWS API Call via CloudTrail"]
    detail = {
      userIdentity = {
        type = ["IAMUser"]
        arn  = [var.canary_user_arn]
      }
    }
  })
}

# Rule 2: honey bucket accessed via CloudTrail S3 data events
# S3 bucket notifications only cover writes/deletes — GetObject comes via CloudTrail
resource "aws_cloudwatch_event_rule" "honey_s3" {
  name        = "honeycloud-honey-s3-trigger"
  description = "Fires on CloudTrail S3 data events for the honey bucket"

  event_pattern = jsonencode({
    source        = ["aws.s3"]
    "detail-type" = ["AWS API Call via CloudTrail"]
    detail = {
      requestParameters = {
        bucketName = [var.honey_bucket_name]
      }
    }
  })
}

# Rule 3: SSRF honeypot custom event from EC2 Flask app
resource "aws_cloudwatch_event_rule" "ssrf_honeypot" {
  name        = "honeycloud-ssrf-trigger"
  description = "Fires when the EC2 IMDS mock is accessed"

  event_pattern = jsonencode({
    source        = ["honeycloud.ssrf"]
    "detail-type" = ["IMDSHoneypotAccess"]
  })
}

resource "aws_cloudwatch_event_target" "canary_iam" {
  rule      = aws_cloudwatch_event_rule.canary_iam.name
  target_id = "EnrichmentLambda"
  arn       = var.enrichment_lambda_arn
}

resource "aws_cloudwatch_event_target" "honey_s3" {
  rule      = aws_cloudwatch_event_rule.honey_s3.name
  target_id = "EnrichmentLambda"
  arn       = var.enrichment_lambda_arn
}

resource "aws_cloudwatch_event_target" "ssrf" {
  rule      = aws_cloudwatch_event_rule.ssrf_honeypot.name
  target_id = "EnrichmentLambda"
  arn       = var.enrichment_lambda_arn
}

resource "aws_lambda_permission" "canary_iam" {
  statement_id  = "AllowEventBridgeCanaryIAM"
  action        = "lambda:InvokeFunction"
  function_name = var.enrichment_lambda_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.canary_iam.arn
}

resource "aws_lambda_permission" "honey_s3" {
  statement_id  = "AllowEventBridgeHoneyS3"
  action        = "lambda:InvokeFunction"
  function_name = var.enrichment_lambda_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.honey_s3.arn
}

resource "aws_lambda_permission" "ssrf" {
  statement_id  = "AllowEventBridgeSSRF"
  action        = "lambda:InvokeFunction"
  function_name = var.enrichment_lambda_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ssrf_honeypot.arn
}
