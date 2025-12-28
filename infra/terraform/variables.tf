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
  description = "L0 Composite の通知先"
  type        = list(string)
  default     = []
}

variable "notification_channels_l2" {
  description = "L2 Composite の通知先"
  type        = list(string)
  default     = []
}

variable "notification_channels_l3" {
  description = "L3 Composite の通知先"
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
    project     = "datadog-poc"
    environment = "poc"
    managed_by  = "terraform"
  }
}
