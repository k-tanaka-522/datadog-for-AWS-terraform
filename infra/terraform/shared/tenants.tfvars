# Tenant configurations for AWS Terraform
# For Datadog, use datadog.tfvars

tenants = {
  tenant-a = {
    name        = "tenant-a"
    cpu         = 256
    memory      = 512
    priority    = 100  # ALB Listener Rule priority
    environment = "poc"
  }
  tenant-b = {
    name        = "tenant-b"
    cpu         = 256
    memory      = 512
    priority    = 101  # ALB Listener Rule priority
    environment = "poc"
  }
  tenant-c = {
    name        = "tenant-c"
    cpu         = 256
    memory      = 512
    priority    = 102  # ALB Listener Rule priority
    environment = "poc"
  }
}
