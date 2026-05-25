resource "aws_sns_topic" "alerts" {
  name = "honeycloud-alerts"
}

resource "aws_sns_topic_subscription" "email_debug" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
