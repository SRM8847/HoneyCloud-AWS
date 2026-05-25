output "canary_user_arn"   { value = aws_iam_user.canary.arn }
output "canary_access_key" { value = aws_iam_access_key.canary.id }
output "canary_secret_key" {
  value     = aws_iam_access_key.canary.secret
  sensitive = true
}
