variable "aws_region"  { default = "us-east-1" }
variable "aws_profile" { default = "default" }

variable "abuseipdb_api_key" { sensitive = true }
variable "slack_webhook_url" {
  sensitive = true
  default   = "none"
}
variable "alert_email" { description = "Email for SNS alert subscription" }

variable "honey_bucket_name" {
  default = "platform-prod-configs-a3f9"
}

variable "canary_key_rotation_count" {
  type    = number
  default = 1
}
