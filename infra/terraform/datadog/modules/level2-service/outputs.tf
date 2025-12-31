# level2-service モジュール 出力定義

output "monitor_ids" {
  description = "L2 Monitor のIDリスト（Composite Monitor で参照）"
  value = merge(
    {
      alb_health       = datadog_monitor.alb_health.id
      ecs_task_stopped = datadog_monitor.ecs_task_stopped.id
      # ecr_vulnerability monitor is disabled (count = 0)
    },
    var.e2e_health_check_enabled ? {
      e2e_health_check = datadog_synthetics_test.e2e_health_check[0].monitor_id
    } : {}
  )
}

output "monitor_names" {
  description = "L2 Monitor の名前リスト"
  value = merge(
    {
      alb_health       = datadog_monitor.alb_health.name
      ecs_task_stopped = datadog_monitor.ecs_task_stopped.name
      # ecr_vulnerability monitor is disabled (count = 0)
    },
    var.e2e_health_check_enabled ? {
      e2e_health_check = datadog_synthetics_test.e2e_health_check[0].name
    } : {}
  )
}

output "synthetics_test_id" {
  description = "E2E Synthetics Test ID（デバッグ用）"
  value       = var.e2e_health_check_enabled ? datadog_synthetics_test.e2e_health_check[0].id : null
}
