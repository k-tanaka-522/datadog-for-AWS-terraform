# ============================================================
# L3 テナント監視 Monitor
# ============================================================
#
# 【L3層の責務】
# テナントごとの詳細な監視（エラー、レイテンシ、ログなど）を行います。
# L0/L1/L2が全て正常でも、特定テナントだけが問題を抱えている場合があります。
#
# 【設計思想】★PoC の核心機能★
# - インフラ障害時（L0/L1/L2）にはL3アラートを抑制
# - テナント固有の問題（アプリバグ、データ不整合等）のみを通知
# - 「原因と結果を分離する」監視設計
#
# 【監視項目】
# 1. ヘルスチェック（無効化 - http.check integration未設定）
# 2. APMエラー数
# 3. ログエラー数
# 4. レイテンシ（p99）
#
# 【for_each パターン】
# このモジュールは main.tf から for_each = var.tenants で呼ばれるため、
# テナントごとにインスタンス化されます。
# ============================================================

# ============================================================
# L3-Health-Check Monitor: ヘルスチェック（無効化）
# ============================================================
#
# 【なぜ無効化されているか】
# http.check は Datadog Agent の HTTP Check integration が必要ですが、
# このPoC環境では設定されていません。
#
# 【代替手段】
# 1. Synthetics API テスト（synthetics.tf）- 外部からのエンドポイント監視
# 2. APMベース監視（下記の apm_errors Monitor）- 内部トレースベース
#
# 【有効化する場合の手順】
# 1. Datadog Agent の設定に http_check を追加
# 2. ECS タスク定義で環境変数を設定
# 3. count = 0 を削除
#
# 【監視の目的】
# テナント別にヘルスチェックエンドポイント（/tenant-id/health）を監視し、
# ALB → ECS → RDS（tenant_idでフィルタしたクエリ）の疎通を確認
# ============================================================
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

# ============================================================
# L3 APM ベース ヘルスチェック Monitor
# ============================================================
#
# 【PoC 検証用】
# 本番環境では以下のいずれか一方を選択:
#   - Synthetics API テスト（synthetics.tf）: 外部からのエンドポイント監視
#   - APM ベース Monitor（本リソース）: 内部トレースベースの監視
#
# 【APM ベースの利点】
#   - Datadog Agent が収集するトレースを活用
#   - レイテンシ、エラー率など詳細メトリクス
#   - 追加コスト不要（既存 APM 課金内）
#
# 【APM ベースの欠点】
#   - Agent障害時に監視できない（L0で補完）
#   - 外部からの疎通確認はできない（Syntheticsで補完）
#
# ============================================================

# ============================================================
# L3-APM-Errors Monitor: APMエラー数監視
# ============================================================
#
# 【監視内容】
# APMトレースで記録されたエラー数を監視
#
# 【PoC の目的】★重要な検証ポイント★
# L1/L2障害時にアプリがエラーを出力 → Composite Monitorで抑制
# 例: RDS障害(L1) → 全テナントのAPIがDBエラー → L3アラートは抑制
#
# 【default_zero() の役割】★Datadogクエリのベストプラクティス★
# default_zero(): エラーが0件の時も「0」として扱う（NO DATAにしない）
#
# なぜ必要か:
# - エラー0件は正常な状態（NO DATAではない）
# - default_zero()がないと、エラーが一度も発生していない場合にNO DATAになる
# - NO DATAと0件を区別することで、正確な監視が可能
#
# 【クエリ解説】
# sum(last_5m):default_zero(sum:trace.fastapi.request.errors{service:${var.service_name}}.as_count())
#   ↑              ↑                ↑                           ↑
# 過去5分合計  0件時は0     FastAPIのエラートレース    カウント形式
#
# 【アラート条件】
# エラー数が閾値を超えた場合（デフォルト: テナントごとに設定）
#
# 【Composite Monitorとの関係】
# このMonitorのIDが l3_monitor_ids[tenant_id] に含まれ、
# L3 Composite Monitorで集約されます。
# L0/L1/L2のいずれかが障害の場合、通知が抑制されます。
# ============================================================
resource "datadog_monitor" "apm_errors" {
  name    = "[L3 APM] ${var.tenant_id} エラー数"
  type    = "metric alert"
  query   = "sum(last_5m):default_zero(sum:trace.fastapi.request.errors{service:${var.service_name}}.as_count()) > ${var.errors_threshold}"
  message = <<-EOT
    [L3 APM] ${var.tenant_id} でAPMエラーが発生しています。
    - エラー数: {{value}}
    - 影響: ${var.tenant_id}
    - 確認内容: APM トレースでエラー詳細を確認

    ※ L1/L2 障害時はこのアラートは Composite Monitor により抑制されます。

    ${join("\n", var.notification_channels)}
  EOT

  monitor_thresholds {
    critical = var.errors_threshold
    warning  = floor(var.errors_threshold / 2)
  }

  tags = concat(
    ["layer:l3", "tenant:${var.tenant_id}", "severity:medium", "type:apm"],
    [for k, v in var.tags : "${k}:${v}"]
  )

  notify_no_data    = false
  renotify_interval = 0
}

# ============================================================
# L3-Log-Errors Monitor: ログエラー数監視
# ============================================================
#
# 【監視内容】
# エラーレベルのログが急増していないかを監視
#
# 【PoC の目的】
# L1/L2障害時にアプリがエラーログを大量出力 → Composite Monitorで抑制
# 例: RDS接続エラー → 全リクエストでDBエラーログ → L3アラートは抑制
#
# 【Log Management の前提】
# この Monitor を使用するには、Datadog の Log Management が有効である必要があります。
# - ECS タスク定義で Datadog Agent のログ収集を有効化
# - アプリケーションが stdout/stderr にログを出力
# - Datadog Agent がログを収集してDatadogに送信
#
# 【クエリ解説】
# logs("status:error service:demo-api").rollup("count").last("5m") > ${var.errors_threshold}
#   ↑           ↑             ↑              ↑           ↑              ↑
# ログ検索  エラー状態  サービス名    カウント集計  過去5分    閾値
#
# 【なぜ service:demo-api でフィルタするのか】
# このPoC環境では、テナント別のタグが付与されていないため、
# サービス全体のエラーログを監視します。
#
# 本番環境では、以下のようにテナント別にフィルタすることを推奨:
# logs("status:error service:demo-api tenant:${var.tenant_id}")
#
# 【アラート条件】
# 過去5分間のエラーログが閾値を超えた場合
# ============================================================
resource "datadog_monitor" "error_logs" {
  name    = "[L3 Log] ${var.tenant_id} エラーログ数"
  type    = "log alert"
  query   = "logs(\"status:error service:demo-api\").rollup(\"count\").last(\"5m\") > ${var.errors_threshold}"
  message = <<-EOT
    [L3 Log] ${var.tenant_id} でエラーログが急増しています。
    - エラーログ数: {{value}}
    - 影響: ${var.tenant_id}
    - 確認内容: Log Explorer でエラー詳細を確認

    ※ L1/L2 障害時はこのアラートは Composite Monitor により抑制されます。

    ${join("\n", var.notification_channels)}
  EOT

  monitor_thresholds {
    critical = var.errors_threshold
    warning  = floor(var.errors_threshold / 2)
  }

  tags = concat(
    ["layer:l3", "tenant:${var.tenant_id}", "severity:medium", "type:log"],
    [for k, v in var.tags : "${k}:${v}"]
  )

  notify_no_data    = false
  renotify_interval = 0
}

# ============================================================
# L3-Latency Monitor: レイテンシ（p99）監視
# ============================================================
#
# 【監視内容】
# APIレスポンスタイムの99パーセンタイル値を監視
#
# 【なぜ p99（99パーセンタイル）か】
# - 平均値（avg）は外れ値に引っ張られる
# - 最大値（max）はスパイクで誤検知しやすい
# - p99（上位1%を除いた最大値）が実用的
#
# 例: 100リクエスト中
# - 99リクエストが100ms以下
# - 1リクエストだけ1000ms（外れ値）
# → 平均: 109ms（外れ値の影響を受ける）
# → p99: 100ms（実際のユーザー体験に近い）
#
# 【クエリ解説】
# avg(last_5m):p99:trace.fastapi.request{service:${var.service_name}}
#   ↑              ↑        ↑                ↑
# 過去5分平均  99%ile  FastAPIリクエスト  サービス名でフィルタ
#
# 【PoC における注意点】
# サービス全体のレイテンシを監視しています。
# 本番環境では、以下のようにテナント別・エンドポイント別に監視することを推奨:
# - resource_name でフィルタ（特定エンドポイント）
# - tenant タグでフィルタ（特定テナント）
#
# 【アラート条件】
# p99レイテンシが閾値（テナントごとに設定）を超えた場合
#
# 【notify_no_data = false の理由】
# - トラフィックが少ない時間帯にNO DATAになる可能性がある
# - レイテンシのNO DATAは障害ではない（リクエストが無いだけ）
# - トラフィック監視は別の Monitor で実施
# ============================================================
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
