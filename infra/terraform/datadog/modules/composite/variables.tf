# composite モジュール 変数定義
# Composite Monitor の作成（L0/L1/L2/L3の親子関係によるアラート抑制）

variable "l0_monitor_ids" {
  description = "L0 Monitor のIDマップ（インフラ基盤: Agent監視等）"
  type        = map(string)
}

variable "l1_monitor_ids" {
  description = "L1 Monitor のIDマップ（コンピュートリソース: RDS/ECS監視）"
  type        = map(string)
}

variable "l2_monitor_ids" {
  description = <<-EOT
    L2 Monitor のIDマップ（サービスレイヤー: ALB/ECS/ECR監視）
    例: {
      alb_health = "123",
      ecs_task_stopped = "456",
      ecr_vulnerability = "789",
      e2e_health_check = "012"  # FR-002-5（E2Eヘルスチェック）
    }
  EOT
  type        = map(string)
}

variable "l3_monitor_ids" {
  description = "L3 Monitor のIDマップ（テナントごと）"
  type        = map(map(string))
  # 例:
  # {
  #   "tenant-a" = { health_check = "123", error_logs = "456", latency = "789" }
  #   "tenant-b" = { health_check = "124", error_logs = "457", latency = "790" }
  # }
}

variable "tenants" {
  description = "テナント定義"
  type = map(object({
    errors_threshold  = number
    latency_threshold = number
  }))
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
