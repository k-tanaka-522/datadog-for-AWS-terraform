# composite モジュール 出力定義

output "composite_ids" {
  description = "Composite Monitor のIDリスト"
  value = {
    l0 = datadog_monitor.l0_composite.id
    l2 = datadog_monitor.l2_composite.id
    l3 = {
      for tenant_id, composite_monitor in datadog_monitor.l3_composite :
      tenant_id => composite_monitor.id
    }
  }
}

output "composite_names" {
  description = "Composite Monitor の名前リスト"
  value = {
    l0 = datadog_monitor.l0_composite.name
    l2 = datadog_monitor.l2_composite.name
    l3 = {
      for tenant_id, composite_monitor in datadog_monitor.l3_composite :
      tenant_id => composite_monitor.name
    }
  }
}
