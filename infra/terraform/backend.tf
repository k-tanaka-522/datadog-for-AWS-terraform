# backend.tf
# Terraform State 管理（S3 + DynamoDB）

terraform {
  backend "s3" {
    bucket         = "datadog-terraform-state"
    key            = "datadog-monitors/terraform.tfstate"
    region         = "ap-northeast-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}
