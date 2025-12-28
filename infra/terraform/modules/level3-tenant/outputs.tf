# level3-tenant モジュール 出力定義

output "monitor_ids" {
  description = "L3 Monitor のIDリスト（テナントごと）"
  value = {
    health_check = datadog_monitor.health_check.id
    error_logs   = datadog_monitor.error_logs.id
    latency      = datadog_monitor.latency.id
  }
}

output "monitor_names" {
  description = "L3 Monitor の名前リスト"
  value = {
    health_check = datadog_monitor.health_check.name
    error_logs   = datadog_monitor.error_logs.name
    latency      = datadog_monitor.latency.name
  }
}

output "tenant_id" {
  description = "テナント識別子"
  value       = var.tenant_id
}
