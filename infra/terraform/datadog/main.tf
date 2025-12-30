# main.tf
# ルートモジュール: 全モジュールの統合

# L0 インフラ監視モジュール
module "level0_infra" {
  source = "./modules/level0-infra"

  rds_instance_id   = var.rds_instance_id
  ecs_cluster_name  = var.ecs_cluster_name
  rds_cpu_threshold = var.rds_cpu_threshold
  rds_mem_threshold = var.rds_mem_threshold

  notification_channels = var.notification_channels_l0
  tags                  = var.common_tags
}

# L2 サービス監視モジュール
module "level2_service" {
  source = "./modules/level2-service"

  alb_target_group    = var.alb_target_group
  alb_fqdn            = var.alb_fqdn
  ecs_cluster_name    = var.ecs_cluster_name
  ecr_repository_name = var.ecr_repository_name

  e2e_health_check_enabled = var.e2e_health_check_enabled

  notification_channels = var.notification_channels_l2
  tags                  = var.common_tags
}

# L3 テナント監視モジュール（for_each でテナント展開）
module "level3_tenant" {
  for_each = var.tenants
  source   = "./modules/level3-tenant"

  tenant_id         = each.key
  health_check_url  = "https://${var.app_domain}/${each.key}/health"
  errors_threshold  = each.value.errors_threshold
  latency_threshold = each.value.latency_threshold

  notification_channels = var.notification_channels_l3
  tags                  = merge(var.common_tags, { tenant = each.key })
}

# Composite Monitor モジュール
module "composite" {
  source = "./modules/composite"

  l0_monitor_ids = module.level0_infra.monitor_ids
  l2_monitor_ids = module.level2_service.monitor_ids
  l3_monitor_ids = {
    for tenant_id, tenant_module in module.level3_tenant :
    tenant_id => tenant_module.monitor_ids
  }
  tenants = var.tenants

  notification_channels = var.notification_channels_composite
  tags                  = var.common_tags
}
