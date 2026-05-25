resource "aws_s3_bucket" "honey" {
  bucket        = var.honey_bucket_name
  force_destroy = true

  tags = {
    Environment = "production"
    Team        = "platform"
    Project     = "honeycloud"
  }
}

resource "aws_s3_bucket_public_access_block" "honey" {
  bucket                  = aws_s3_bucket.honey.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Covers write/delete events — reads (GetObject) come via CloudTrail data events
resource "aws_s3_bucket_notification" "honey" {
  bucket      = aws_s3_bucket.honey.id
  eventbridge = true
}

resource "aws_s3_object" "lure_db_config" {
  bucket  = aws_s3_bucket.honey.id
  key     = "configs/database.yml"
  content = <<-EOT
    production:
      adapter: postgresql
      host: prod-db-cluster.us-east-1.rds.amazonaws.com
      port: 5432
      database: app_production
      username: app_prod_user
      password: <%= ENV['DATABASE_PASSWORD'] %>
      pool: 10
  EOT
}

resource "aws_s3_object" "lure_deploy_key" {
  bucket  = aws_s3_bucket.honey.id
  key     = "deploy/github-actions-deploy.env"
  content = <<-EOT
    AWS_REGION=us-east-1
    ECR_REPOSITORY=platform/app
    EKS_CLUSTER_NAME=prod-eks-cluster
    DEPLOY_ROLE_ARN=arn:aws:iam::123456789012:role/github-actions-deploy
  EOT
}

resource "aws_s3_object" "lure_tf_vars" {
  bucket  = aws_s3_bucket.honey.id
  key     = "terraform/prod.tfvars"
  content = <<-EOT
    environment         = "production"
    vpc_cidr            = "10.0.0.0/16"
    db_instance_class   = "db.r6g.large"
    eks_node_count      = 6
    eks_node_type       = "m6i.xlarge"
    domain              = "internal.example.com"
  EOT
}
