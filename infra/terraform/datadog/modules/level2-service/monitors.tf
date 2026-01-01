# ============================================================
# L2 サービス監視 Monitor
# ============================================================
#
# 【L2層の責務】
# アプリケーションサービス全体（ALB、ECS、E2Eヘルスチェック）を監視します。
# L0/L1が正常でも、L2（サービスレイヤー）が壊れると全テナントに影響します。
#
# 【設計思想】
# - L1（RDS）が正常でも、ALBやECSタスクの問題でサービス停止がありえる
# - L2は「サービス全体の疎通」を監視する層
# - Composite Monitorで L0/L1障害時にはL2アラートを抑制
#
# 【監視項目】
# 1. ALB Target Group Health
# 2. ECS Task 異常停止（イベント監視）
# 3. ECR 脆弱性（無効化 - スキャン未設定）
# 4. ALB→API→RDS E2Eヘルスチェック（Synthetics Test）
#
# ============================================================

# ============================================================
# L2-ALB-Health Monitor: ALB Target Group Health
# ============================================================
#
# 【監視内容】
# ALB配下の全テナントのTarget Groupのヘルシーホスト数を監視
#
# 【重要な設計判断】★マルチテナント対応★
# 実際のTarget Group名: demo-api-tenant-acme-tg, demo-api-tenant-globex-tg...
# ワイルドカード（demo-api-tenant*）で全Target Groupを集計
#
# 【クエリ解説】
# sum:aws.applicationelb.healthy_host_count{targetgroup:targetgroup/demo-api-tenant*}
#   ↑                                        ↑
# 全TGの合計                           ワイルドカード（*）で全テナントを包含
#
# 【Datadog タグ形式の注意点】
# CloudWatchのTarget Group名は "demo-api-tenant-acme-tg" だが、
# Datadogでは "targetgroup/demo-api-tenant-acme-tg/xxxx" 形式のタグになる
# → クエリでは "targetgroup:targetgroup/demo-api-tenant*" と指定
#
# 【アラート条件】
# ヘルシーホストの合計が閾値以下（デフォルト: 0）
# つまり「全テナントのTarget Groupで少なくとも1つはヘルシーホストがある」ことを確認
#
# 【notify_no_data = false の理由】
# - CloudWatchメトリクスの遅延は障害ではない
# - ALBが存在しない期間（削除後など）にNO DATAアラートが出るのを防ぐ
# ============================================================
resource "datadog_monitor" "alb_health" {
  name    = "[L2] ALB Target Group Health"
  type    = "metric alert"
  query   = "avg(last_5m):sum:aws.applicationelb.healthy_host_count{targetgroup:targetgroup/demo-api-tenant*} <= ${var.alb_healthy_host_threshold}"
  message = <<-EOT
    [L2] ALB Target Groupのヘルシーホストが${var.alb_healthy_host_threshold}になりました。
    - Target Group Pattern: demo-api-tenant-*-tg
    - Healthy Hosts (合計): {{value}}
    - 影響: 全テナント（サービス停止の可能性）

    ${join("\n", var.notification_channels)}
  EOT

  monitor_thresholds {
    critical = var.alb_healthy_host_threshold
    warning  = 1
  }

  tags = concat(
    ["layer:l2", "resource:alb", "severity:critical"],
    [for k, v in var.tags : "${k}:${v}"]
  )

  notify_no_data    = false
  renotify_interval = 0
}

# ============================================================
# L2-ECS-Task Monitor: ECS Task 異常停止（Event Monitor）
# ============================================================
#
# 【監視内容】
# ECS タスクの異常停止イベントを監視
#
# 【Event Monitor の利点】★メトリクス監視との違い★
# - タスク停止の「理由」が分かる（OOM、DeploymentFailed、Healthcheck失敗等）
# - メトリクス遅延に依存しない（リアルタイム検知）
# - トラブルシューティングがしやすい
#
# 【クエリ解説】
# events("source:ecs status:error ecs.cluster-name:${var.ecs_cluster_name}")
#   ↑         ↑           ↑            ↑
#  イベント  ECS由来   エラー状態   クラスタ名でフィルタ
#
# .rollup("count").last("5m") > 0
#   ↑                  ↑          ↑
# カウント集計    過去5分    1件でもあればアラート
#
# 【検知できる異常例】
# - OOM（Out of Memory）によるタスク強制停止
# - Healthcheck失敗による自動再起動
# - デプロイ失敗（新しいタスク定義が起動しない）
# - ECS Agent の問題
#
# 【アラート条件】
# 過去5分間にエラーイベントが1件以上発生
#
# 【message の変数】
# {{event.title}}: イベントタイトル（"Task stopped"等）
# {{event.text}}: イベント詳細（停止理由を含む）
# ============================================================
resource "datadog_monitor" "ecs_task_stopped" {
  name    = "[L2] ECS Task 異常停止"
  type    = "event-v2 alert"
  query   = "events(\"source:ecs status:error ecs.cluster-name:${var.ecs_cluster_name}\").rollup(\"count\").last(\"5m\") > 0"
  message = <<-EOT
    [L2] ECS Taskが異常停止しました。
    - Cluster: ${var.ecs_cluster_name}
    - Event: {{event.title}}
    - 影響: 該当テナント

    詳細: {{event.text}}

    ${join("\n", var.notification_channels)}
  EOT

  monitor_thresholds {
    critical = 0
  }

  tags = concat(
    ["layer:l2", "resource:ecs", "severity:high"],
    [for k, v in var.tags : "${k}:${v}"]
  )

  notify_no_data    = false
  renotify_interval = 0
}

# ============================================================
# L2-ECR-Vuln Monitor: ECR 脆弱性監視（無効化）
# ============================================================
#
# 【なぜ無効化されているか】
# ECR の脆弱性スキャンが有効化されていない、または
# Datadog に aws.ecr.vulnerability.critical メトリクスが送信されていないため。
#
# 【有効化する場合の手順】
# 1. ECR で脆弱性スキャンを有効化
#    - AWS Console → ECR → リポジトリ設定 → Image scanning
# 2. Datadog AWS Integration で ECR メトリクスを有効化
# 3. count = 0 を count = 1 に変更
#
# 【監視の目的】
# コンテナイメージに Critical レベルの脆弱性が含まれていないかを監視
# セキュリティインシデントを未然に防ぐため。
#
# 【アラート条件】
# Critical脆弱性が1件以上検出された場合
#
# 【対応策】
# - 脆弱性を含むパッケージを更新
# - ベースイメージを最新化
# - Dockerfile の FROM を更新して再ビルド
# ============================================================
resource "datadog_monitor" "ecr_vulnerability" {
  count   = 0 # Disabled: ECR vulnerability scanning not enabled or metrics not available
  name    = "[L2] ECR 脆弱性（Critical）"
  type    = "metric alert"
  query   = "avg(last_15m):sum:aws.ecr.vulnerability.critical{repository_name:${var.ecr_repository_name}} > 0"
  message = <<-EOT
    [L2] ECR イメージにCritical脆弱性が検出されました。
    - Repository: ${var.ecr_repository_name}
    - Critical Vulnerabilities: {{value}}
    - 影響: 該当イメージを使用している環境

    対応: イメージを最新化してください。

    ${join("\n", var.notification_channels)}
  EOT

  monitor_thresholds {
    critical = 0
  }

  tags = concat(
    ["layer:l2", "resource:ecr", "severity:high"],
    [for k, v in var.tags : "${k}:${v}"]
  )

  notify_no_data    = false
  renotify_interval = 0
}

# ============================================================
# L2-E2E-Health: ALB→API→RDS E2Eヘルスチェック（Synthetics Test）
# ============================================================
#
# 【監視内容】
# 外部からALBにHTTPリクエストを送り、API→RDSの疎通を確認
#
# 【Synthetics Test とは】★Datadog の重要機能★
# - Datadog が提供する外部監視サービス
# - 世界中のリージョンから定期的にHTTPリクエストを送信
# - レスポンス内容、レスポンスタイム、ステータスコードを検証
# - ユーザー視点での監視が可能
#
# 【なぜ必要か】
# - 内部監視（APM、メトリクス）だけでは、外部からの疎通は分からない
# - ALBのリスナー設定ミス、セキュリティグループの問題などを検知
# - 「サービスが本当にユーザーから見えているか」を確認
#
# 【e2e_health_check_enabled = false の場合】
# Syntheticsはコストがかかるため、PoC環境では無効化されている場合がある
# count = var.e2e_health_check_enabled ? 1 : 0 で制御
#
# 【監視対象URL】
# http://${var.alb_fqdn}/tenant-a/health
#   ↑                      ↑
# ALBのFQDN            代表テナントのヘルスチェックエンドポイント
#
# 【assertion（検証項目）】
# 1. statusCode = 200
# 2. responseTime < 5000ms（5秒）
# 3. body に "status":"ok" が含まれる
#
# 【tick_every = 300】
# 5分ごとに実行（頻度はコストとバランス）
#
# 【retry 設定】
# - 2回リトライ
# - 5分間隔でリトライ
# → 一時的なネットワーク問題で誤検知しないように
#
# 【locations】
# aws:ap-northeast-1（東京リージョン）から実行
# 本番では複数リージョンから監視することを推奨
# ============================================================
resource "datadog_synthetics_test" "e2e_health_check" {
  count = var.e2e_health_check_enabled ? 1 : 0

  name    = "[L2] ALB→API→RDS E2Eヘルスチェック"
  type    = "api"
  subtype = "http"
  status  = "live"

  request_definition {
    method = "GET"
    url    = "http://${var.alb_fqdn}/tenant-a/health" # 代表テナントでインフラ疎通確認
  }

  assertion {
    type     = "statusCode"
    operator = "is"
    target   = "200"
  }

  assertion {
    type     = "responseTime"
    operator = "lessThan"
    target   = "5000" # 5秒
  }

  assertion {
    type     = "body"
    operator = "contains"
    target   = "\"status\":\"ok\""
  }

  locations = ["aws:ap-northeast-1"]

  options_list {
    tick_every = 300 # 5分ごと
    retry {
      count    = 2
      interval = 300 # 5分間隔でリトライ
    }
  }

  message = <<-EOT
    [L2] ALB→API→RDS E2Eヘルスチェックが失敗しました。
    - URL: http://${var.alb_fqdn}/tenant-a/health
    - 影響: 全テナント（サービス停止の可能性）
    - 確認内容: ALB → ECS → RDS 疎通

    対応: ALB、ECS、RDSの疎通を確認してください。

    ${join("\n", var.notification_channels)}
  EOT

  tags = concat(
    ["layer:l2", "resource:e2e", "severity:critical"],
    [for k, v in var.tags : "${k}:${v}"]
  )
}
