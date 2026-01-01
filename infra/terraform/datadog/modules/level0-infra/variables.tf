# level0-infra モジュール 変数定義
# L0 インフラ基盤監視 Monitor の作成

variable "ecs_cluster_name" {
  description = "ECS Cluster 名（例: myapp-cluster）"
  type        = string
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
