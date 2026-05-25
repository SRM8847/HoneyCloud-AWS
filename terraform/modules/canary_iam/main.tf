resource "random_id" "suffix" {
  byte_length = 4
  keepers = {
    rotation = var.rotation_count
  }
}

resource "aws_iam_user" "canary" {
  name = "svc-deploy-pipeline-${random_id.suffix.hex}"
  path = "/service/"
  tags = {
    Environment = "production"
    Team        = "platform"
    Managed     = "terraform"
    Project     = "honeycloud"
  }
}

# Zero permissions — no policy attached.
# CloudTrail logs the API call attempt regardless.
resource "aws_iam_access_key" "canary" {
  user = aws_iam_user.canary.name
}
