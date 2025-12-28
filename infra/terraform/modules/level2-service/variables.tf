# level2-service モジュール 変数定義
# L2 サービス監視 Monitor の作成

variable "alb_target_group" {
  description = "ALB Target Group 名（例: myapp-tg）"
  type        = string
}

variable "alb_fqdn" {
  description = "ALB FQDN（例: myapp-1234567890.ap-northeast-1.elb.amazonaws.com）"
  type        = string
}

variable "ecs_cluster_name" {
  description = "ECS Cluster 名（例: myapp-cluster）"
  type        = string
}

variable "ecr_repository_name" {
  description = "ECR リポジトリ名（例: myapp）"
  type        = string
  default     = "myapp"
}

variable "alb_healthy_host_threshold" {
  description = "ALB ヘルシーホスト数の閾値（この値以下でアラート）"
  type        = number
  default     = 0
}

variable "e2e_health_check_enabled" {
  description = "E2Eヘルスチェック有効化フラグ（Synthetic Monitoring使用）"
  type        = bool
  default     = true
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
