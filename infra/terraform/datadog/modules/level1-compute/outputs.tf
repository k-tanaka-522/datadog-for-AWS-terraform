# level1-compute モジュール 出力定義

output "monitor_ids" {
  description = "L1 Monitor のIDリスト（Composite Monitor で参照）"
  value = {
    rds_cpu     = datadog_monitor.rds_cpu.id
    rds_conn    = datadog_monitor.rds_conn.id
    rds_mem     = datadog_monitor.rds_mem.id
    rds_storage = datadog_monitor.rds_storage.id
    # ecs_tasks は CloudWatch連携未対応のため無効化（L2 ECS Task異常停止で代替）
  }
}

output "monitor_names" {
  description = "L1 Monitor の名前リスト"
  value = {
    rds_cpu     = datadog_monitor.rds_cpu.name
    rds_conn    = datadog_monitor.rds_conn.name
    rds_mem     = datadog_monitor.rds_mem.name
    rds_storage = datadog_monitor.rds_storage.name
    # ecs_tasks は CloudWatch連携未対応のため無効化（L2 ECS Task異常停止で代替）
  }
}
