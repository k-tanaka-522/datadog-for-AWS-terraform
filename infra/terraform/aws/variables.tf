# AWS Region
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-1"
}

# Datadog API Key
variable "dd_api_key" {
  description = "Datadog API Key"
  type        = string
  sensitive   = true
}

# Tenants configuration
variable "tenants" {
  description = "Tenant configurations"
  type = map(object({
    name        = string
    cpu         = number
    memory      = number
    priority    = number
    environment = string
  }))
}
