module "canary_iam" {
  source         = "./modules/canary_iam"
  rotation_count = var.canary_key_rotation_count
}

module "cloudtrail" {
  source            = "./modules/cloudtrail"
  aws_region        = var.aws_region
  honey_bucket_name = var.honey_bucket_name
}

module "honey_s3" {
  source            = "./modules/honey_s3"
  honey_bucket_name = var.honey_bucket_name
}

module "sns_slack" {
  source      = "./modules/sns_slack"
  alert_email = var.alert_email
}

module "lambda_enrichment" {
  source            = "./modules/lambda_enrichment"
  lambda_zip_path   = "${path.module}/../lambda/enrichment.zip"
  sns_topic_arn     = module.sns_slack.topic_arn
  abuseipdb_api_key = var.abuseipdb_api_key
  depends_on        = [module.sns_slack]
}

module "eventbridge" {
  source                 = "./modules/eventbridge"
  canary_user_arn        = module.canary_iam.canary_user_arn
  honey_bucket_name      = var.honey_bucket_name
  enrichment_lambda_arn  = module.lambda_enrichment.function_arn
  enrichment_lambda_name = module.lambda_enrichment.function_name
  depends_on             = [module.lambda_enrichment]
}

module "ssrf_honeypot" {
  source     = "./modules/ssrf_honeypot"
  aws_region = var.aws_region
  depends_on = [module.eventbridge]
}
