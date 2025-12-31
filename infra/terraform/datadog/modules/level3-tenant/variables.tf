# level3-tenant モジュール 変数定義
# L3 テナント監視 Monitor の作成（for_each対応）

variable "tenant_id" {
  description = "テナント識別子（例: tenant-a）"
  type        = string
}

variable "service_name" {
  description = "APM サービス名（例: demo-api）"
  type        = string
  default     = "demo-api"
}

variable "health_check_url" {
  description = "ヘルスチェックURL（例: https://myapp.example.com/tenant-a/health）"
  type        = string
}

variable "errors_threshold" {
  description = "エラーログ数の閾値（5分間）"
  type        = number
  default     = 10
}

variable "latency_threshold" {
  description = "レイテンシ閾値（ms、p99）"
  type        = number
  default     = 1000
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
