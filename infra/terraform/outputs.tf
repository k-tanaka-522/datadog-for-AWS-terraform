# outputs.tf
# 出力定義

output "l0_monitor_ids" {
  description = "L0 Monitor のIDリスト"
  value       = module.level0_infra.monitor_ids
}

output "l2_monitor_ids" {
  description = "L2 Monitor のIDリスト"
  value       = module.level2_service.monitor_ids
}

output "l3_monitor_ids" {
  description = "L3 Monitor のIDリスト（テナントごと）"
  value = {
    for tenant_id, tenant_module in module.level3_tenant :
    tenant_id => tenant_module.monitor_ids
  }
}

output "composite_monitor_ids" {
  description = "Composite Monitor のIDリスト"
  value       = module.composite.composite_ids
}
