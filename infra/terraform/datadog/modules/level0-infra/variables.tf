# level0-infra モジュール 変数定義
# L0 インフラ監視 Monitor の作成

variable "rds_instance_id" {
  description = "RDS インスタンス識別子（例: myapp-db）"
  type        = string
}

variable "ecs_cluster_name" {
  description = "ECS Cluster 名（例: myapp-cluster）"
  type        = string
}

variable "rds_cpu_threshold" {
  description = "RDS CPU使用率の閾値（%）"
  type        = number
  default     = 95
}

variable "rds_cpu_warning" {
  description = "RDS CPU使用率の警告閾値（%）"
  type        = number
  default     = 80
}

variable "rds_conn_threshold" {
  description = "RDS 接続数の閾値（絶対値）"
  type        = number
  default     = 80
}

variable "rds_mem_threshold" {
  description = <<-EOT
    RDS 空きメモリの閾値（バイト）
    例: 1GB = 1073741824、500MB = 524288000
    ⭐ AWS CloudWatchでは総メモリ量メトリクスが提供されていないため、絶対値で監視
  EOT
  type        = number
  default     = 1073741824 # 1GB
}

variable "rds_storage_threshold" {
  description = "DEPRECATED: 使用されません。rds_storage_threshold_bytes を使用してください。"
  type        = number
  default     = 5
}

variable "rds_storage_threshold_bytes" {
  description = <<-EOT
    RDS 空きストレージの閾値（バイト）
    例: 5GB = 5368709120、10GB = 10737418240
    ⭐ CloudWatch には total_storage_space がないため絶対値で監視
  EOT
  type        = number
  default     = 5368709120 # 5GB
}

variable "rds_storage_warning_bytes" {
  description = "RDS 空きストレージの警告閾値（バイト）"
  type        = number
  default     = 10737418240 # 10GB
}

variable "ecs_tasks_threshold" {
  description = "ECS Running Tasks の閾値（この値以下でアラート）"
  type        = number
  default     = 0
}

variable "notification_channels" {
  description = "通知先（Slack、Email、PagerDuty等）"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Monitor に付与するタグ"
  type        = map(string)
  default     = {}
}
