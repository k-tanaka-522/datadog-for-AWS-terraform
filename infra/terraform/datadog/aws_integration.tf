# aws_integration.tf
# Datadog AWS Integration configuration (using new resource)

# AWS Integration using the new resource (recommended)
resource "datadog_integration_aws_account" "main" {
  aws_account_id = var.aws_account_id
  aws_partition  = "aws"
  account_tags   = ["project:datadog-poc", "env:poc", "team:sre"]

  # AWS authentication via IAM role
  auth_config {
    aws_auth_config_role {
      role_name = "DatadogAWSIntegrationRole"
      # external_id is computed by Datadog
    }
  }

  # Collect from ap-northeast-1 only for PoC
  aws_regions {
    include_only = ["ap-northeast-1"]
  }

  # Resources to collect
  resources_config {
    cloud_security_posture_management_collection = false
    extended_collection                          = false
  }

  # Traces config - disabled for PoC (no X-Ray tracing)
  traces_config {
    xray_services {
      include_only = []
    }
  }

  # Metrics collection config
  metrics_config {
    automute_enabled          = true
    collect_cloudwatch_alarms = true
    collect_custom_metrics    = false
    enabled                   = true

    namespace_filters {
      exclude_only = [
        "AWS/ElastiCache",
        "AWS/ES",
        "AWS/Kinesis",
        "AWS/Lambda",
        "AWS/Route53",
        "AWS/S3",
        "AWS/SQS",
        "AWS/SNS"
      ]
    }
  }

  # Logs config
  logs_config {
    lambda_forwarder {}
  }
}

# Output the external ID for IAM role configuration
output "aws_integration_external_id" {
  description = "External ID for Datadog AWS Integration (use this in IAM role trust policy)"
  value       = datadog_integration_aws_account.main.auth_config.aws_auth_config_role.external_id
  sensitive   = true
}

output "aws_integration_account_id" {
  description = "AWS Account ID integrated with Datadog"
  value       = datadog_integration_aws_account.main.aws_account_id
}
