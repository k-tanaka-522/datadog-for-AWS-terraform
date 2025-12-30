# Main Terraform configuration for AWS infrastructure
# This file serves as the entry point for the AWS infrastructure stack

# Locals
locals {
  common_tags = {
    Project     = "datadog-monitoring"
    Environment = "poc"
    ManagedBy   = "terraform"
  }
}
