# variables.tf
# ルートモジュールの変数定義

# Datadog API Key/APP Key（環境変数から注入）
variable "datadog_api_key" {
  description = "Datadog API Key"
  type        = string
  sensitive   = true
}

variable "datadog_app_key" {
  description = "Datadog APP Key"
  type        = string
  sensitive   = true
}

# AWS アカウントID
variable "aws_account_id" {
  description = "AWS Account ID for Datadog Integration"
  type        = string
}

# AWS External ID (for Datadog IAM Role)
variable "aws_external_id" {
  description = "External ID for Datadog AWS Integration IAM Role"
  type        = string
  sensitive   = true
}

# AWS リソース識別子
variable "rds_instance_id" {
  description = "RDS インスタンス識別子（例: myapp-db）"
  type        = string
}

variable "ecs_cluster_name" {
  description = "ECS Cluster 名（例: myapp-cluster）"
  type        = string
}

variable "alb_target_group" {
  description = "ALB Target Group 名（例: myapp-tg）"
  type        = string
}

variable "alb_fqdn" {
  description = "ALB FQDN（例: myapp-1234567890.ap-northeast-1.elb.amazonaws.com）⭐ FR-002-5で使用"
  type        = string
}

variable "ecr_repository_name" {
  description = "ECR リポジトリ名（例: myapp）"
  type        = string
  default     = "myapp"
}

variable "app_domain" {
  description = "アプリケーションドメイン（例: myapp.example.com）"
  type        = string
}

variable "service_name" {
  description = "APM サービス名（例: demo-api）"
  type        = string
  default     = "demo-api"
}

# 閾値
variable "rds_cpu_threshold" {
  description = "RDS CPU使用率の閾値（%）"
  type        = number
  default     = 95
}

variable "rds_mem_threshold" {
  description = "RDS 空きメモリの閾値（バイト、デフォルト: 1GB）"
  type        = number
  default     = 1073741824 # 1GB
}

# E2Eヘルスチェック有効化フラグ
variable "e2e_health_check_enabled" {
  description = "E2Eヘルスチェック有効化フラグ（Synthetic Monitoring使用）"
  type        = bool
  default     = true
}

# テナント定義
variable "tenants" {
  description = "テナント定義（テナントID → 閾値）"
  type = map(object({
    errors_threshold  = number
    latency_threshold = number
  }))
}

# 通知先（階層別）
variable "notification_channels_l0" {
  description = "L0 インフラ基盤監視の通知先"
  type        = list(string)
  default     = []
}

variable "notification_channels_l1" {
  description = "L1 コンピュートリソース監視の通知先"
  type        = list(string)
  default     = []
}

variable "notification_channels_l2" {
  description = "L2 サービス監視の通知先"
  type        = list(string)
  default     = []
}

variable "notification_channels_l3" {
  description = "L3 テナント監視の通知先"
  type        = list(string)
  default     = []
}

variable "notification_channels_composite" {
  description = "Composite Monitor の通知先"
  type        = list(string)
  default     = []
}

# 共通タグ
variable "common_tags" {
  description = "全Monitor に付与する共通タグ"
  type        = map(string)
  default = {
    project    = "datadog-poc"
    env        = "poc" # Datadog Unified Service Tagging 標準に準拠
    managed_by = "terraform"
  }
}
