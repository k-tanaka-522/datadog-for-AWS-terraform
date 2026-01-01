# ============================================================
# Composite Monitor モジュール
# ============================================================
#
# 【このファイルの目的】
# マルチテナント監視における「アラート抑制の階層構造」を実装します。
# インフラ障害時に大量のアプリアラートが通知されるのを防ぎ、
# 根本原因（インフラ）だけを通知する仕組みです。
#
# 【階層構造の設計思想】
# L0 (インフラ基盤) → L1 (コンピュート) → L2 (サービス) → L3 (テナント)
# 親の層で障害が起きている場合、子の層のアラートは抑制します。
#
# 例: RDS障害(L1)が発生した場合
#   → 全テナントのAPIがエラーを出すが、通知は「RDS障害」のみ
#   → テナントごとの「エラーログ増加」アラートは抑制される
#
# 【参考資料】
# - Datadog Composite Monitor: https://docs.datadoghq.com/monitors/types/composite/
# - PoC検証報告書: docs/POC_REPORT.md
# ============================================================

# ============================================================
# L0 Composite Monitor（インフラ基盤）
# ============================================================
#
# 【責務】
# 最上位の監視層。Datadog Agentやネットワークなど、
# 「監視基盤そのもの」が正常かを判定します。
#
# 【アラート条件】
# L0の個別Monitor（APMトレース疎通など）のいずれかがアラート
# → L0 Composite がアラート
#
# 【重要な設計判断】
# - OR条件で結合（いずれかが障害 = インフラ基盤障害）
# - notify_no_data = false
#   理由: Composite Monitor自体はメトリクスを取得しないため、
#         NO DATAにはならない。個別Monitorで制御する。
#
# 【クエリ構文の解説】
# join(" || ", [...]) → Monitor IDを " || " で結合
# 例: 12345 || 12346 → 「Monitor 12345 または 12346 がアラート」
# ============================================================
resource "datadog_monitor" "l0_composite" {
  name    = "[L0 Composite] インフラ基盤障害"
  type    = "composite"
  query   = join(" || ", [for monitor_id in values(var.l0_monitor_ids) : "${monitor_id}"])
  message = <<-EOT
    [L0 Composite] インフラ基盤で障害が発生しました。
    - 影響: 全テナント（監視基盤停止）
    - 対応: インフラチームが調査中

    詳細: {{#is_alert}}
    以下のL0 Monitorがアラート状態です:
    {{#each alerting_monitors}}
    - {{this.name}}
    {{/each}}
    {{/is_alert}}

    ${join("\n", var.notification_channels)}
  EOT

  tags = concat(
    ["layer:l0-infra", "composite:true", "severity:critical"],
    [for k, v in var.tags : "${k}:${v}"]
  )

  notify_no_data    = false
  renotify_interval = 0
}

# ============================================================
# L1 Composite Monitor（コンピュートリソース）
# ============================================================
#
# 【責務】
# RDS、ECSなど「アプリケーションが動作する基盤」を監視します。
#
# 【アラート抑制ロジック】
# L0障害時にはL1アラートを抑制します。
# 理由: L0（監視基盤）が壊れている場合、L1（RDS/ECS）の
#       監視データも信頼できないため。
#
# 【クエリ構文の解説】★重要★】
# (L1_A || L1_B) && !L0
#          ↑              ↑
#    L1のいずれか    かつ L0が正常
#
# 括弧が必要な理由:
# - Datadog Composite Monitorは演算子優先度があります
# - 括弧なしだと: A || B && !C → A || (B && !C) と解釈される（予期しない動作）
# - 括弧ありだと: (A || B) && !C → 正しく「AまたはB、かつCでない」
#
# 【重要】
# !${datadog_monitor.l0_composite.id} → L0 Composite Monitor の否定
# つまり「L0が正常（OKまたはWARN）の場合のみL1アラートを通知」
# ============================================================
resource "datadog_monitor" "l1_composite" {
  name    = "[L1 Composite] コンピュートリソース障害"
  type    = "composite"
  query   = "(${join(" || ", [for monitor_id in values(var.l1_monitor_ids) : "${monitor_id}"])}) && !${datadog_monitor.l0_composite.id}"
  message = <<-EOT
    [L1 Composite] コンピュートリソースで障害が発生しました。
    - 影響: 全テナント（RDS/ECS障害）
    - 対応: インフラチームが調査中

    詳細: {{#is_alert}}
    以下のL1 Monitorがアラート状態です:
    {{#each alerting_monitors}}
    - {{this.name}}
    {{/each}}
    {{/is_alert}}

    注: L0障害中の場合、このアラートは抑制されます。

    ${join("\n", var.notification_channels)}
  EOT

  tags = concat(
    ["layer:l1-compute", "composite:true", "severity:critical"],
    [for k, v in var.tags : "${k}:${v}"]
  )

  notify_no_data    = false
  renotify_interval = 0
}

# ============================================================
# L2 Composite Monitor（サービスレイヤー）
# ============================================================
#
# 【責務】
# ALB、ECSタスク、E2Eヘルスチェックなど「サービス全体」を監視します。
#
# 【アラート抑制ロジック】★PoC の核心機能★
# L0またはL1で障害が起きている場合、L2アラートを抑制します。
# 理由: RDS障害(L1) → API全体がエラーを返す(L2)
#       でも通知すべきは「RDS障害」であり「APIエラー」ではない
#
# 【クエリ構文の解説】
# (L2_A || L2_B) && !L0 && !L1
#
# 演算子優先度:
# 1. 括弧内の OR条件を先に評価 → (L2_A || L2_B)
# 2. 次にAND条件を左から評価 → && !L0 && !L1
#
# つまり:
# 「L2のいずれかが障害」かつ「L0が正常」かつ「L1が正常」
# の場合のみアラートを通知
#
# 【実運用での効果】
# テナントが100個ある場合でも、RDS障害時には:
# - 通知されるアラート: [L1] RDS CPU使用率 1件のみ
# - 抑制されるアラート: [L2] ALB Health、[L3] テナントごとエラー 100件以上
# ============================================================
resource "datadog_monitor" "l2_composite" {
  name    = "[L2 Composite] サービスレイヤー障害"
  type    = "composite"
  query   = "(${join(" || ", [for monitor_id in values(var.l2_monitor_ids) : "${monitor_id}"])}) && !${datadog_monitor.l0_composite.id} && !${datadog_monitor.l1_composite.id}"
  message = <<-EOT
    [L2 Composite] サービスレイヤーで障害が発生しました。
    - 影響: 該当サービス
    - 対応: アプリケーションチームが調査中

    詳細: {{#is_alert}}
    以下のL2 Monitorがアラート状態です:
    {{#each alerting_monitors}}
    - {{this.name}}
    {{/each}}
    {{/is_alert}}

    注: L0/L1障害中の場合、このアラートは抑制されます。

    ${join("\n", var.notification_channels)}
  EOT

  tags = concat(
    ["layer:l2-service", "composite:true", "severity:high"],
    [for k, v in var.tags : "${k}:${v}"]
  )

  notify_no_data    = false
  renotify_interval = 0
}

# ============================================================
# L3 Composite Monitor（テナント別）
# ============================================================
#
# 【責務】
# テナントごとの詳細監視（エラーログ、レイテンシ、エラー率など）
#
# 【for_each パターン】★Terraform の核心テクニック★
# for_each = var.tenants を使うことで、tenants.tfvars にテナントを
# 追加するだけで、自動的にMonitorが作成されます。
#
# 例: tenants.tfvars
#   tenants = {
#     "acme" = { ... }
#     "globex" = { ... }
#   }
# → 2つのL3 Composite Monitorが自動作成される
#
# 【アラート抑制ロジック】
# (L3_tenant_A || L3_tenant_B) && !L0 && !L1 && !L2
#
# 【設計意図】
# - L0/L1/L2のいずれかで障害 → テナント別アラートは全て抑制
# - L0/L1/L2が全て正常 → テナント固有の問題として通知
#
# 【実運用での効果】
# 例: RDS障害(L1)発生時
#   - [L1 Composite] RDS障害 → 通知される
#   - [L3 Composite] acme 障害 → 抑制される（!L1 が false）
#   - [L3 Composite] globex 障害 → 抑制される（!L1 が false）
#
# 例: acme テナントのアプリバグ発生時
#   - L0/L1/L2 全て正常 → !L0 && !L1 && !L2 が true
#   - [L3 Composite] acme 障害 → 通知される
#   - [L3 Composite] globex 障害 → 通知されない（そもそもアラート状態でない）
#
# 【Terraformリソース管理】
# for_each で作成されるリソースは以下のように管理されます:
# - terraform state list で確認:
#   module.composite.datadog_monitor.l3_composite["acme"]
#   module.composite.datadog_monitor.l3_composite["globex"]
# - terraform taint で個別に操作可能:
#   terraform taint 'module.composite.datadog_monitor.l3_composite["acme"]'
# ============================================================
resource "datadog_monitor" "l3_composite" {
  for_each = var.tenants

  name    = "[L3 Composite] ${each.key} 障害"
  type    = "composite"
  query   = "(${join(" || ", [for monitor_id in values(var.l3_monitor_ids[each.key]) : "${monitor_id}"])}) && !${datadog_monitor.l0_composite.id} && !${datadog_monitor.l1_composite.id} && !${datadog_monitor.l2_composite.id}"
  message = <<-EOT
    [L3 Composite] ${each.key} で障害が発生しました。
    - 影響: ${each.key} のみ
    - 対応: 開発チームが調査中

    詳細: {{#is_alert}}
    以下のL3 Monitorがアラート状態です:
    {{#each alerting_monitors}}
    - {{this.name}}
    {{/each}}
    {{/is_alert}}

    注: L0/L1/L2障害中の場合、このアラートは抑制されます。

    ${join("\n", var.notification_channels)}
  EOT

  tags = concat(
    ["layer:l3-tenant", "tenant:${each.key}", "composite:true", "severity:medium"],
    [for k, v in var.tags : "${k}:${v}"]
  )

  notify_no_data    = false
  renotify_interval = 0
}
