# level3-tenant モジュール Monitor定義
# L3 テナント監視 Monitor（3個、テナントごと）

# FR-003-1: ヘルスチェック（RDS疎通含む）
# Disabled: http.check requires Datadog Agent HTTP Check integration (not configured)
# 代替: synthetics.tf (Synthetics API テスト) または health_check_apm (APM ベース) を使用
resource "datadog_monitor" "health_check" {
  count   = 0
  name    = "[L3] ${var.tenant_id} ヘルスチェック（RDS疎通含む）"
  type    = "service check"
  query   = "\"http.check\".over(\"url:${var.health_check_url}\").by(\"*\").last(2).count_by_status()"
  message = <<-EOT
    [L3] ${var.tenant_id} のヘルスチェック（RDS疎通含む）が失敗しました。
    - URL: ${var.health_check_url}
    - 影響: ${var.tenant_id} のみ
    - 確認内容: ALB → ECS → RDS（tenant_id='${var.tenant_id}'）疎通

    対応: 以下を確認してください。
    1. ${var.tenant_id} のアプリケーションが正常に動作しているか
    2. RDSへの接続が正常か（tenant_idでフィルタしたクエリが実行できるか）
    3. /{tenant_id}/health エンドポイントが正常にレスポンスを返すか

    ${join("\n", var.notification_channels)}
  EOT

  monitor_thresholds {
    critical = 1
    ok       = 1
  }

  tags = concat(
    ["layer:l3", "tenant:${var.tenant_id}", "severity:high"],
    [for k, v in var.tags : "${k}:${v}"]
  )

  notify_no_data    = true
  no_data_timeframe = 10
  renotify_interval = 0
}

# =============================================================================
# L3 APM ベース ヘルスチェック Monitor
# =============================================================================
#
# 【PoC 検証用】
# 本番環境では以下のいずれか一方を選択:
#   - Synthetics API テスト（synthetics.tf）: 外部からのエンドポイント監視
#   - APM ベース Monitor（本リソース）: 内部トレースベースの監視
#
# APM ベースの利点:
#   - Datadog Agent が収集するトレースを活用
#   - レイテンシ、エラー率など詳細メトリクス
#   - 追加コスト不要（既存 APM 課金内）
#
# =============================================================================

# FR-003-1: APM ベース ヘルスチェック（エラー率監視）
# NOTE: FastAPI フレームワーク使用のため trace.fastapi.request.* メトリクスを使用
# NOTE: PoC ではサービス全体のエラーを監視。本番では resource_name や tenant タグでフィルタ。
resource "datadog_monitor" "health_check_apm" {
  name    = "[L3 APM] ${var.tenant_id} ヘルスチェック（エラー率監視）"
  type    = "metric alert"
  query   = "sum(last_5m):sum:trace.fastapi.request.errors{service:${var.service_name}}.as_count() > 0"
  message = <<-EOT
    [L3 APM] ${var.tenant_id} のヘルスチェックエンドポイントでエラーが発生しています。
    - エラー数: {{value}}
    - 影響: ${var.tenant_id} のみ
    - 確認内容: APM トレースに記録されたエラー（内部監視）

    対応: 以下を確認してください。
    1. ${var.tenant_id} のアプリケーションログを確認
    2. RDS への接続が正常か（tenant_id='${var.tenant_id}' のクエリ実行）
    3. APM トレース詳細を確認（https://app.datadoghq.com/apm/traces）
    4. ECS タスクのヘルスステータスを確認

    ${join("\n", var.notification_channels)}
  EOT

  monitor_thresholds {
    critical = 0 # 1件でもエラーが発生したらアラート
  }

  tags = concat(
    ["layer:l3", "tenant:${var.tenant_id}", "severity:high", "type:apm"],
    [for k, v in var.tags : "${k}:${v}"]
  )

  notify_no_data    = true
  no_data_timeframe = 10 # 10分間データがない場合も通知
  renotify_interval = 0
}

# L3-Error Monitor（Log Monitor - disabled: requires Log Management enabled）
resource "datadog_monitor" "error_logs" {
  count   = 0 # Disabled: Log Management not enabled in this Datadog account
  name    = "[L3] ${var.tenant_id} エラーログ数"
  type    = "log alert"
  query   = "logs(\"status:error tenant:${var.tenant_id}\").rollup(\"count\").last(\"5m\") > ${var.errors_threshold}"
  message = <<-EOT
    [L3] ${var.tenant_id} のエラーログが5分間で${var.errors_threshold}件を超えました。
    - Count: {{value}}
    - 影響: ${var.tenant_id} のみ

    詳細: {{log.message}}

    ${join("\n", var.notification_channels)}
  EOT

  monitor_thresholds {
    critical = var.errors_threshold
    warning  = floor(var.errors_threshold / 2)
  }

  tags = concat(
    ["layer:l3", "tenant:${var.tenant_id}", "severity:medium"],
    [for k, v in var.tags : "${k}:${v}"]
  )

  notify_no_data    = false
  renotify_interval = 0
}

# L3-Latency Monitor（APM Monitor）
# NOTE: FastAPI フレームワーク使用のため trace.fastapi.request メトリクスを使用
# NOTE: PoC ではサービス全体のレイテンシを監視。本番では resource_name や tenant タグでフィルタ。
resource "datadog_monitor" "latency" {
  name    = "[L3] ${var.tenant_id} レイテンシ（p99）"
  type    = "metric alert"
  query   = "avg(last_5m):p99:trace.fastapi.request{service:${var.service_name}} > ${var.latency_threshold}"
  message = <<-EOT
    [L3] ${var.tenant_id} のレイテンシ（p99）が${var.latency_threshold}msを超えました。
    - Latency: {{value}}ms
    - 影響: ${var.tenant_id} のみ

    ${join("\n", var.notification_channels)}
  EOT

  monitor_thresholds {
    critical = var.latency_threshold
    warning  = floor(var.latency_threshold * 0.5)
  }

  tags = concat(
    ["layer:l3", "tenant:${var.tenant_id}", "severity:medium"],
    [for k, v in var.tags : "${k}:${v}"]
  )

  notify_no_data    = false
  renotify_interval = 0
}
