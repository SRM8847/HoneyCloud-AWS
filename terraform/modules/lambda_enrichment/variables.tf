variable "lambda_zip_path"   { type = string }
variable "sns_topic_arn"     { type = string }
variable "abuseipdb_api_key" {
  type      = string
  sensitive = true
}
