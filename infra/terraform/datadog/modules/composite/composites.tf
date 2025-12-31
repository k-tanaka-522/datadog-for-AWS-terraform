# composite モジュール Composite Monitor定義
# Composite Monitor（L0/L2/L3、アラート抑制）

# L0 Composite Monitor
resource "datadog_monitor" "l0_composite" {
  name    = "[L0 Composite] インフラ基盤障害"
  type    = "composite"
  query   = join(" || ", [for monitor_id in values(var.l0_monitor_ids) : "${monitor_id}"])
  message = <<-EOT
    [L0 Composite] インフラ基盤で障害が発生しました。
    - 影響: 全テナント
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
    ["layer:l0", "composite:true", "severity:critical"],
    [for k, v in var.tags : "${k}:${v}"]
  )

  notify_no_data    = false
  renotify_interval = 0
}

# L2 Composite Monitor
# L0障害時にL2アラートを抑制（PoCの核心機能）
resource "datadog_monitor" "l2_composite" {
  name    = "[L2 Composite] サービスレイヤー障害"
  type    = "composite"
  query   = "${join(" || ", [for monitor_id in values(var.l2_monitor_ids) : "${monitor_id}"])} && !${datadog_monitor.l0_composite.id}"
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

    注: L0障害中の場合、このアラートは抑制されます。

    ${join("\n", var.notification_channels)}
  EOT

  tags = concat(
    ["layer:l2", "composite:true", "severity:high"],
    [for k, v in var.tags : "${k}:${v}"]
  )

  notify_no_data    = false
  renotify_interval = 0
}

# L3 Composite Monitor
# L0/L2障害時にL3アラートを抑制（PoCの核心機能）
resource "datadog_monitor" "l3_composite" {
  for_each = var.tenants

  name    = "[L3 Composite] ${each.key} 障害"
  type    = "composite"
  query   = "${join(" || ", [for monitor_id in values(var.l3_monitor_ids[each.key]) : "${monitor_id}"])} && !${datadog_monitor.l0_composite.id} && !${datadog_monitor.l2_composite.id}"
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

    注: L0/L2障害中の場合、このアラートは抑制されます。

    ${join("\n", var.notification_channels)}
  EOT

  tags = concat(
    ["layer:l3", "tenant:${each.key}", "composite:true", "severity:medium"],
    [for k, v in var.tags : "${k}:${v}"]
  )

  notify_no_data    = false
  renotify_interval = 0
}
