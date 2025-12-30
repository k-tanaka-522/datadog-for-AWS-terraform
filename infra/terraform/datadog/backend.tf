# backend.tf
# Terraform State 管理（S3 + DynamoDB）

terraform {
  backend "s3" {
    bucket         = "datadog-poc-terraform-state"
    key            = "datadog/terraform.tfstate"
    region         = "ap-northeast-1"
    encrypt        = true
    dynamodb_table = "datadog-poc-terraform-state-lock"
  }
}
