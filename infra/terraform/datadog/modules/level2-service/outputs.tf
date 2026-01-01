# level2-service モジュール 出力定義

output "monitor_ids" {
  description = "L2 Monitor のIDリスト（Composite Monitor用、Synthetics除外）"
  value = {
    alb_health       = datadog_monitor.alb_health.id
    ecs_task_stopped = datadog_monitor.ecs_task_stopped.id
    # Synthetics は Composite Monitor で正しく評価されないため除外
    # ecr_vulnerability monitor is disabled (count = 0)
  }
}

output "monitor_names" {
  description = "L2 Monitor の名前リスト（Synthetics除外）"
  value = {
    alb_health       = datadog_monitor.alb_health.name
    ecs_task_stopped = datadog_monitor.ecs_task_stopped.name
    # Synthetics は Composite Monitor で正しく評価されないため除外
    # ecr_vulnerability monitor is disabled (count = 0)
  }
}

# Synthetics monitor ID は別途出力（参照用、Composite非対応）
output "synthetics_monitor_id" {
  description = "L2 Synthetics Monitor ID（Composite非対応のため別出力）"
  value       = var.e2e_health_check_enabled ? datadog_synthetics_test.e2e_health_check[0].monitor_id : null
}

output "synthetics_test_id" {
  description = "E2E Synthetics Test ID（デバッグ用）"
  value       = var.e2e_health_check_enabled ? datadog_synthetics_test.e2e_health_check[0].id : null
}
