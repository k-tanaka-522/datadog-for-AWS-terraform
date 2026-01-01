# ============================================================
# Datadog Terraform ルートモジュール
# ============================================================
#
# 【このファイルの目的】
# 全てのDatadog監視モジュール（L0/L1/L2/L3/Composite）を統合し、
# 階層型マルチテナント監視を構築します。
#
# 【モジュール構成】
# L0（インフラ基盤）→ L1（コンピュート）→ L2（サービス）→ L3（テナント）
# ↓ Monitor ID を受け渡し
# Composite（アラート抑制ロジック）
#
# 【Terraform モジュールパターンのベストプラクティス】
# - モジュール間の依存関係は outputs 経由で明示的に定義
# - 各モジュールは独立してテスト可能
# - ルートモジュール（このファイル）で全体を統合
#
# 【参考資料】
# - Terraform モジュール: https://www.terraform.io/language/modules
# - Datadog Provider: https://registry.terraform.io/providers/DataDog/datadog/latest/docs
# ============================================================

# ============================================================
# L0 インフラ基盤監視モジュール
# ============================================================
#
# 【責務】
# 監視システムそのものが正常に動作しているかを監視
# - APMトレース疎通（Agent + アプリの死活確認）
#
# 【outputs】
# monitor_ids: L0 Monitor の ID マップ
# → Composite モジュールで使用
#
# 【notification_channels_l0】
# L0専用の通知先（通常は最優先で対応すべきチーム）
# 例: ["@slack-infra-critical", "@pagerduty-oncall"]
# ============================================================
module "level0_infra" {
  source = "./modules/level0-infra"

  ecs_cluster_name = var.ecs_cluster_name

  notification_channels = var.notification_channels_l0
  tags                  = var.common_tags
}

# ============================================================
# L1 コンピュートリソース監視モジュール
# ============================================================
#
# 【責務】
# アプリケーションが動作する基盤（RDS、ECS）を監視
# - RDS: CPU、メモリ、接続数、ストレージ
# - ECS: タスク数（現在は無効化、L2で代替）
#
# 【outputs】
# monitor_ids: L1 Monitor の ID マップ
# → Composite モジュールで使用
#
# 【通知先の分離】
# notification_channels_l1: L1専用の通知先
# L0とは異なるチーム（DBチーム等）に通知する場合に使用
# ============================================================
module "level1_compute" {
  source = "./modules/level1-compute"

  rds_instance_id   = var.rds_instance_id
  ecs_cluster_name  = var.ecs_cluster_name
  rds_cpu_threshold = var.rds_cpu_threshold
  rds_mem_threshold = var.rds_mem_threshold

  notification_channels = var.notification_channels_l1
  tags                  = var.common_tags
}

# ============================================================
# L2 サービス監視モジュール
# ============================================================
#
# 【責務】
# アプリケーションサービス全体を監視
# - ALB Target Group Health
# - ECS Task 異常停止（イベント監視）
# - ECR 脆弱性（無効化）
# - E2Eヘルスチェック（Synthetics Test、オプション）
#
# 【outputs】
# monitor_ids: L2 Monitor の ID マップ
# → Composite モジュールで使用
#
# 【e2e_health_check_enabled】
# Synthetics Test は有料機能のため、PoC環境では無効化可能
# var.e2e_health_check_enabled = false で無効化
# ============================================================
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

# ============================================================
# L3 テナント監視モジュール（for_each 展開）
# ============================================================
#
# 【責務】
# テナントごとの詳細監視
# - APMエラー数
# - ログエラー数
# - レイテンシ（p99）
#
# 【for_each パターン】★Terraform の核心テクニック★
# for_each = var.tenants により、テナントごとにモジュールが展開されます。
#
# 例: var.tenants = { "acme" = {...}, "globex" = {...} }
# → 以下のモジュールインスタンスが作成される:
#   - module.level3_tenant["acme"]
#   - module.level3_tenant["globex"]
#
# 【Terraform State での管理】
# terraform state list で確認:
#   module.level3_tenant["acme"].datadog_monitor.apm_errors
#   module.level3_tenant["globex"].datadog_monitor.apm_errors
#
# 【テナント追加の手順】
# 1. tenants.tfvars に新しいテナントを追加
# 2. terraform apply を実行
# → 自動的に新しいテナントの Monitor が作成される
#
# 【outputs】
# monitor_ids: 各テナントの Monitor ID マップ
# → Composite モジュールで使用
#
# 【health_check_url】
# テナント別のヘルスチェックエンドポイント
# 例: http://demo-api.example.com/acme/health
# ============================================================
module "level3_tenant" {
  for_each = var.tenants
  source   = "./modules/level3-tenant"

  tenant_id         = each.key
  service_name      = var.service_name
  health_check_url  = "http://${var.app_domain}/${each.key}/health"
  errors_threshold  = each.value.errors_threshold
  latency_threshold = each.value.latency_threshold

  notification_channels = var.notification_channels_l3
  tags                  = merge(var.common_tags, { tenant = each.key })
}

# ============================================================
# Composite Monitor モジュール
# ============================================================
#
# 【責務】★PoC の核心機能★
# 階層型アラート抑制を実装
# - L0 障害時 → L1/L2/L3 のアラートを抑制
# - L1 障害時 → L2/L3 のアラートを抑制
# - L2 障害時 → L3 のアラートを抑制
#
# 【Monitor ID の受け渡し】
# 各層のモジュールから outputs 経由で Monitor ID を受け取り、
# Composite Monitor のクエリで使用します。
#
# l0_monitor_ids:
#   module.level0_infra.monitor_ids
#   例: { "agent" = "12345678" }
#
# l1_monitor_ids:
#   module.level1_compute.monitor_ids
#   例: { "rds_cpu" = "12345679", "rds_conn" = "12345680", ... }
#
# l2_monitor_ids:
#   module.level2_service.monitor_ids
#   例: { "alb_health" = "12345681", "ecs_task_stopped" = "12345682", ... }
#
# l3_monitor_ids:
#   テナントごとの Monitor ID マップ
#   例: {
#     "acme"   = { "apm_errors" = "12345683", "error_logs" = "12345684", ... }
#     "globex" = { "apm_errors" = "12345685", "error_logs" = "12345686", ... }
#   }
#
# 【for式による変換】★Terraform 高度なテクニック★
# l3_monitor_ids = {
#   for tenant_id, tenant_module in module.level3_tenant :
#   tenant_id => tenant_module.monitor_ids
# }
#
# これにより、for_each で展開されたモジュールの outputs を
# マップ形式で Composite モジュールに渡します。
#
# 【tenants 変数の渡し方】
# Composite モジュールは L3 Composite Monitor を作成する際に
# for_each = var.tenants を使用するため、tenants変数を渡します。
#
# 【notification_channels_composite】
# Composite Monitor 専用の通知先
# 通常は各層の通知先と同じだが、「根本原因のみ通知」という
# 特性上、エスカレーション先を変えることも可能
# ============================================================
module "composite" {
  source = "./modules/composite"

  l0_monitor_ids = module.level0_infra.monitor_ids
  l1_monitor_ids = module.level1_compute.monitor_ids
  l2_monitor_ids = module.level2_service.monitor_ids
  l3_monitor_ids = {
    for tenant_id, tenant_module in module.level3_tenant :
    tenant_id => tenant_module.monitor_ids
  }
  tenants = var.tenants

  notification_channels = var.notification_channels_composite
  tags                  = var.common_tags
}
