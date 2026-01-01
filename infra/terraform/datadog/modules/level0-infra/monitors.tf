# ============================================================
# L0 インフラ基盤監視 Monitor
# ============================================================
#
# 【L0層の責務】
# 監視システムそのものが正常に動作しているかを監視します。
# この層が障害になると、全ての監視が機能しなくなります。
#
# 【設計判断】
# ECS Fargate では従来のAgent監視（datadog.agent.up）が使えないため、
# APMトレースの疎通で代替します。
#
# 理由:
# - Fargate では Datadog Agent はサイドカーコンテナとして動作
# - サービスチェック（datadog.agent.up）は送信されない（Fargate の制限）
# - 代替として APM トレースの疎通を監視
#   → Agent稼働 + アプリケーション稼働の両方を確認できる
#
# 【参考資料】
# - Fargate監視: https://docs.datadoghq.com/integrations/ecs_fargate/
# ============================================================

# ============================================================
# L0-APM Monitor: APMトレース疎通監視
# ============================================================
#
# 【監視内容】
# APMトレース（trace.fastapi.request.hits）が途絶えていないかを監視
#
# 【アラート条件】
# 過去5分間のトレース数が1未満（ = トレースが来ていない）
#
# 【重要なクエリパラメータ】
# - sum(last_5m): 過去5分間の合計
# - .as_count(): メトリクスをカウントとして扱う（レート変換しない）
# - {env:poc}: 環境タグでフィルタ（本番/開発を分離）
# - < 1: 1件未満（つまり0件）でアラート
#
# 【考えられる障害原因】
# 1. ECS タスクが停止している（DeploymentFailed、OOM等）
# 2. Datadog Agent サイドカーが起動失敗（DD_API_KEY不正等）
# 3. アプリケーション自体がクラッシュ
# 4. ネットワーク問題でトレースが送信できない
#
# 【notify_no_data = true の理由】★重要★
# - NO DATA（データが全く来ない）は重大な障害サイン
# - 通常のMonitorは notify_no_data = false だが、L0だけは例外
# - no_data_timeframe = 10: 10分間データが来なければNO DATAアラート
#
# 【Composite Monitorとの関係】
# このMonitorのIDが l0_monitor_ids に含まれ、
# L0 Composite Monitorで集約されます。
# ============================================================
resource "datadog_monitor" "agent" {
  name    = "[L0] APM トレース疎通"
  type    = "metric alert"
  query   = "sum(last_5m):sum:trace.fastapi.request.hits{env:poc}.as_count() < 1"
  message = <<-EOT
    [L0] APMトレースが途絶えました（Agent または アプリケーション停止の可能性）。
    - Service: demo-api
    - Cluster: ${var.ecs_cluster_name}
    - 影響: 全テナント（監視停止またはサービス停止）

    確認事項:
    - ECS タスクが起動しているか
    - Datadog Agent サイドカーが動作しているか
    - DD_API_KEY が正しく設定されているか

    ${join("\n", var.notification_channels)}
  EOT

  monitor_thresholds {
    critical = 1
  }

  tags = concat(
    ["layer:l0-infra", "resource:apm", "severity:critical"],
    [for k, v in var.tags : "${k}:${v}"]
  )

  notify_no_data    = true
  no_data_timeframe = 10
  renotify_interval = 0
}
