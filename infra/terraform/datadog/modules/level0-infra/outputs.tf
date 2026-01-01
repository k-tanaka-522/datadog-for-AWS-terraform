# level0-infra モジュール 出力定義

output "monitor_ids" {
  description = "L0 Monitor のIDリスト（Composite Monitor で参照）"
  value = {
    agent = datadog_monitor.agent.id
  }
}

output "monitor_names" {
  description = "L0 Monitor の名前リスト"
  value = {
    agent = datadog_monitor.agent.name
  }
}
