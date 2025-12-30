# Datadog Terraform configuration
# This file contains Datadog-specific variables

# Datadog credentials
datadog_api_key    = "aed4f15712d995ace257f0fa1c56f967"
datadog_app_key    = "abde34c74ab97d6b335a32d31e61ca5650106d99"

# AWS resource identifiers
rds_instance_id    = "datadog-poc-db"
ecs_cluster_name   = "datadog-poc-cluster"
alb_target_group   = "demo-api"
alb_fqdn           = "datadog-poc-alb-2037337052.ap-northeast-1.elb.amazonaws.com"
app_domain         = "datadog-poc-alb-2037337052.ap-northeast-1.elb.amazonaws.com"

# Tenant definitions with thresholds
tenants = {
  tenant-a = {
    errors_threshold  = 10
    latency_threshold = 3000
  }
  tenant-b = {
    errors_threshold  = 10
    latency_threshold = 3000
  }
  tenant-c = {
    errors_threshold  = 10
    latency_threshold = 3000
  }
}
