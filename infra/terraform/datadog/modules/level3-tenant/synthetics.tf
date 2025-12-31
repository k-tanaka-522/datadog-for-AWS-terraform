# =============================================================================
# L3 テナント別 Synthetics API テスト
# =============================================================================
#
# 【PoC 検証用】
# 本番環境では以下のいずれか一方を選択:
#   - Synthetics API テスト（本ファイル）: 外部からのエンドポイント監視
#   - APM ベース Monitor（monitors.tf）: 内部トレースベースの監視
#
# Synthetics の利点:
#   - 実際のユーザー視点での可用性監視
#   - ALB → ECS → RDS の E2E 疎通確認
#   - Datadog Agent 不要（外部からの HTTP リクエスト）
#
# =============================================================================

resource "datadog_synthetics_test" "health_check" {
  name    = "[L3 Synthetics] ${var.tenant_id} ヘルスチェック（E2E疎通確認）"
  type    = "api"
  subtype = "http"
  status  = "live"

  message = <<-EOT
    [L3 Synthetics] ${var.tenant_id} のヘルスチェック（E2E疎通確認）が失敗しました。
    - URL: ${var.health_check_url}
    - 影響: ${var.tenant_id} のみ
    - 確認内容: 外部からの ALB → ECS → RDS（tenant_id='${var.tenant_id}'）疎通

    対応: 以下を確認してください。
    1. ALB のターゲットグループが正常か（ヘルスチェック通過しているか）
    2. ECS タスクが起動しているか
    3. ${var.tenant_id} のデータベース接続が正常か
    4. /{tenant_id}/health エンドポイントが正常にレスポンスを返すか

    ${join("\n", var.notification_channels)}
  EOT

  locations = ["aws:ap-northeast-1"] # 東京リージョンから実行

  request_definition {
    method = "GET"
    url    = var.health_check_url
  }

  assertion {
    type     = "statusCode"
    operator = "is"
    target   = "200"
  }

  assertion {
    type     = "body"
    operator = "contains"
    target   = "\"status\":\"ok\""
  }

  assertion {
    type     = "responseTime"
    operator = "lessThan"
    target   = "2000" # 2秒以内
  }

  options_list {
    tick_every           = 60 # 1分間隔（30秒も選択可能）
    min_failure_duration = 0  # 即座にアラート
    min_location_failed  = 1  # 1ロケーションで失敗したらアラート

    retry {
      count    = 2
      interval = 300 # 5分後にリトライ
    }

    monitor_options {
      renotify_interval = 0 # 再通知なし
    }
  }

  tags = concat(
    ["layer:l3", "tenant:${var.tenant_id}", "severity:high", "type:synthetics"],
    [for k, v in var.tags : "${k}:${v}"]
  )
}
