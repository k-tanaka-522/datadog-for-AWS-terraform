terraform {
  backend "s3" {
    bucket         = "datadog-poc-terraform-state"
    key            = "aws/terraform.tfstate"
    region         = "ap-northeast-1"
    encrypt        = true
    dynamodb_table = "datadog-poc-terraform-state-lock"
  }
}
