# level0-infra モジュール 出力定義

output "monitor_ids" {
  description = "L0 Monitor のIDリスト（Composite Monitor で参照）"
  value = {
    rds_cpu     = datadog_monitor.rds_cpu.id
    rds_conn    = datadog_monitor.rds_conn.id
    rds_mem     = datadog_monitor.rds_mem.id
    rds_storage = datadog_monitor.rds_storage.id
    ecs_tasks   = datadog_monitor.ecs_tasks.id
    # vpc_flow disabled - Log Management not enabled
    agent = datadog_monitor.agent.id
  }
}

output "monitor_names" {
  description = "L0 Monitor の名前リスト"
  value = {
    rds_cpu     = datadog_monitor.rds_cpu.name
    rds_conn    = datadog_monitor.rds_conn.name
    rds_mem     = datadog_monitor.rds_mem.name
    rds_storage = datadog_monitor.rds_storage.name
    ecs_tasks   = datadog_monitor.ecs_tasks.name
    # vpc_flow disabled - Log Management not enabled
    agent = datadog_monitor.agent.name
  }
}
