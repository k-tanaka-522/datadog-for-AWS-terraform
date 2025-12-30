# composite モジュール 出力定義

output "composite_ids" {
  description = "Composite Monitor のIDリスト"
  value = {
    l0 = datadog_monitor.l0_composite.id
    # L2/L3 disabled due to query validation issues
  }
}

output "composite_names" {
  description = "Composite Monitor の名前リスト"
  value = {
    l0 = datadog_monitor.l0_composite.name
    # L2/L3 disabled due to query validation issues
  }
}
