output "canary_access_key" {
  value     = module.canary_iam.canary_access_key
  sensitive = false
}

output "canary_secret_key" {
  value     = module.canary_iam.canary_secret_key
  sensitive = true
}

output "canary_user_arn" {
  value = module.canary_iam.canary_user_arn
}

output "honey_bucket_name" {
  value = var.honey_bucket_name
}

output "enrichment_lambda_name" {
  value = module.lambda_enrichment.function_name
}

output "ssrf_honeypot_ip" {
  value = module.ssrf_honeypot.instance_public_ip
}
