# level3-tenant モジュール 出力定義

output "monitor_ids" {
  description = "L3 Monitor のIDリスト（テナントごと）"
  value = {
    # health_check disabled - http.check requires Agent HTTP Check (not configured)
    health_check_apm = datadog_monitor.health_check_apm.id
    # error_logs disabled - Log Management not enabled
    latency = datadog_monitor.latency.id
  }
}

output "monitor_names" {
  description = "L3 Monitor の名前リスト"
  value = {
    # health_check disabled - http.check requires Agent HTTP Check (not configured)
    health_check_apm = datadog_monitor.health_check_apm.name
    # error_logs disabled - Log Management not enabled
    latency = datadog_monitor.latency.name
  }
}

output "tenant_id" {
  description = "テナント識別子"
  value       = var.tenant_id
}
