# ============================================================
# L1 コンピュートリソース監視 Monitor
# ============================================================
#
# 【L1層の責務】
# アプリケーションが動作する基盤（RDS、ECS）を監視します。
# L0（監視基盤）が正常でも、L1（DB/コンピュート）が壊れると
# 全テナントに影響が出ます。
#
# 【設計思想】
# - RDS障害 → 全テナントのAPIがエラーを返す
# - でも通知すべきは「RDS障害」であり「各テナントのエラー」ではない
# → Composite Monitorで下位層（L2/L3）のアラートを抑制
#
# 【監視項目】
# 1. RDS CPU使用率
# 2. RDS 接続数
# 3. RDS 空きメモリ
# 4. RDS 空きストレージ
# （ECS タスク数監視は無効化 - L2で代替）
#
# ============================================================

# ============================================================
# L1-RDS-CPU Monitor: CPU使用率監視
# ============================================================
#
# 【監視内容】
# RDS インスタンスのCPU使用率を監視
#
# 【アラート条件】
# 過去5分間の平均CPU使用率が閾値を超えた場合
#
# 【重要なクエリパラメータ】
# - avg(last_5m): 過去5分間の平均（スパイクを無視）
# - avg:aws.rds.cpuutilization: CloudWatchメトリクス
# - {dbinstanceidentifier:xxx}: 特定のRDSインスタンスに絞る
#
# 【notify_no_data = false の理由】
# - CloudWatchメトリクスは1分間隔で送信される
# - 一時的な遅延でNO DATAになることがある
# - L1層では「メトリクス遅延 ≠ 障害」と判断
# - NO DATAアラートはL0層のみで監視
#
# 【Composite Monitorとの関係】
# このMonitorがアラートになると:
# 1. L1 Composite Monitor がアラート（L0が正常な場合）
# 2. L2/L3 Composite Monitor は抑制される（!L1 が false）
# ============================================================
resource "datadog_monitor" "rds_cpu" {
  name    = "[L1] RDS CPU使用率"
  type    = "metric alert"
  query   = "avg(last_5m):avg:aws.rds.cpuutilization{dbinstanceidentifier:${var.rds_instance_id}} > ${var.rds_cpu_threshold}"
  message = <<-EOT
    [L1] RDS CPU使用率が${var.rds_cpu_threshold}%を超えました。
    - DB: ${var.rds_instance_id}
    - CPU: {{value}}%
    - 影響: 全テナント

    ${join("\n", var.notification_channels)}
  EOT

  monitor_thresholds {
    critical = var.rds_cpu_threshold
    warning  = var.rds_cpu_warning
  }

  tags = concat(
    ["layer:l1-compute", "resource:rds", "severity:critical"],
    [for k, v in var.tags : "${k}:${v}"]
  )

  notify_no_data    = false
  renotify_interval = 0
}

# ============================================================
# L1-RDS-Conn Monitor: 接続数監視
# ============================================================
#
# 【監視内容】
# RDS への同時接続数を監視
#
# 【なぜ重要か】
# - RDS には最大接続数の制限がある（インスタンスタイプ依存）
# - 接続プールが枯渇すると新規リクエストが処理できなくなる
# - テナント数が増えると接続数も増加する
#
# 【アラート条件】
# 接続数が閾値を超えた場合（デフォルト: 80接続）
#
# 【対応策】
# - RDS インスタンスタイプのアップグレード
# - アプリケーション側の接続プール設定見直し
# - 不要なコネクションの削除
# ============================================================
resource "datadog_monitor" "rds_conn" {
  name    = "[L1] RDS 接続数"
  type    = "metric alert"
  query   = "avg(last_5m):avg:aws.rds.database_connections{dbinstanceidentifier:${var.rds_instance_id}} > ${var.rds_conn_threshold}"
  message = <<-EOT
    [L1] RDS 接続数が${var.rds_conn_threshold}を超えました。
    - DB: ${var.rds_instance_id}
    - 接続数: {{value}}
    - 影響: 全テナント

    ${join("\n", var.notification_channels)}
  EOT

  monitor_thresholds {
    critical = var.rds_conn_threshold
    warning  = 60
  }

  tags = concat(
    ["layer:l1-compute", "resource:rds", "severity:critical"],
    [for k, v in var.tags : "${k}:${v}"]
  )

  notify_no_data    = false
  renotify_interval = 0
}

# ============================================================
# L1-RDS-Mem Monitor: 空きメモリ監視
# ============================================================
#
# 【監視内容】
# RDS インスタンスの空きメモリ（バイト単位）
#
# 【アラート条件】
# 空きメモリが閾値を下回った場合（デフォルト: 1GB = 1073741824バイト）
#
# 【なぜバイト単位か】
# CloudWatch/Datadog の aws.rds.freeable_memory メトリクスは
# バイト単位で送信されるため、そのまま使用。
#
# 【メモリ不足の影響】
# - クエリのキャッシュヒット率低下 → レスポンスタイム悪化
# - スワップ発生 → さらに性能劣化
# - OOM（Out of Memory）でインスタンスクラッシュの可能性
#
# 【対応策】
# - RDS インスタンスタイプのアップグレード
# - 不要なコネクションの削除
# - 長時間実行されているクエリの調査
# ============================================================
resource "datadog_monitor" "rds_mem" {
  name    = "[L1] RDS 空きメモリ"
  type    = "metric alert"
  query   = "avg(last_5m):avg:aws.rds.freeable_memory{dbinstanceidentifier:${var.rds_instance_id}} < ${var.rds_mem_threshold}"
  message = <<-EOT
    [L1] RDS 空きメモリが${var.rds_mem_threshold}バイト（${floor(var.rds_mem_threshold / 1073741824)}GB）を下回りました。
    - DB: ${var.rds_instance_id}
    - 空きメモリ: {{value}}バイト
    - 影響: 全テナント

    対応: RDSインスタンスタイプの変更を検討してください。

    ${join("\n", var.notification_channels)}
  EOT

  monitor_thresholds {
    critical = var.rds_mem_threshold
    warning  = var.rds_mem_threshold * 2 # 空きメモリが2GB以下で警告
  }

  tags = concat(
    ["layer:l1-compute", "resource:rds", "severity:critical"],
    [for k, v in var.tags : "${k}:${v}"]
  )

  notify_no_data    = false
  renotify_interval = 0
}

# ============================================================
# L1-RDS-Storage Monitor: 空きストレージ監視
# ============================================================
#
# 【監視内容】
# RDS インスタンスの空きストレージ容量
#
# 【なぜ絶対値（バイト）で監視するのか】
# CloudWatch/Datadog には total_storage_space メトリクスが存在しないため、
# 使用率（%）での監視ができません。
# そのため、絶対値（バイト）で閾値を設定します。
#
# 【アラート条件】
# 空きストレージが5GB以下でCritical、10GB以下でWarning
#
# 【ストレージ不足の影響】
# - INSERTクエリが失敗する
# - ログローテーションが停止する
# - トランザクションログが蓄積してディスクフル
# - RDSインスタンスが自動停止する可能性
#
# 【対応策】
# - RDS ストレージの拡張（オンラインで可能）
# - 不要なデータの削除（古いログテーブル等）
# - テーブルの圧縮（VACUUM FULL）
#
# 【Terraformでの閾値設定】
# variables.tf で以下のように設定:
#   rds_storage_threshold_bytes = 5368709120  # 5GB
#   rds_storage_warning_bytes   = 10737418240 # 10GB
# ============================================================
resource "datadog_monitor" "rds_storage" {
  name    = "[L1] RDS 空きストレージ"
  type    = "metric alert"
  query   = "avg(last_5m):avg:aws.rds.free_storage_space{dbinstanceidentifier:${var.rds_instance_id}} < ${var.rds_storage_threshold_bytes}"
  message = <<-EOT
    [L1] RDS 空きストレージが${floor(var.rds_storage_threshold_bytes / 1073741824)}GBを下回りました。
    - DB: ${var.rds_instance_id}
    - 空きストレージ: {{value}}バイト
    - 影響: 全テナント

    対応: ストレージの拡張またはデータ削除を検討してください。

    ${join("\n", var.notification_channels)}
  EOT

  monitor_thresholds {
    critical = var.rds_storage_threshold_bytes
    warning  = var.rds_storage_warning_bytes
  }

  tags = concat(
    ["layer:l1-compute", "resource:rds", "severity:critical"],
    [for k, v in var.tags : "${k}:${v}"]
  )

  notify_no_data    = false
  renotify_interval = 0
}

# ============================================================
# L1-ECS-Tasks Monitor（無効化）
# ============================================================
#
# 【なぜ無効化されているか】
# aws.ecs.service.desired メトリクスがDatadogに存在しないため。
#
# 【代替手段】
# L2層の [L2] ECS Task 異常停止 Monitor で、
# ECS イベントベースの監視を実施しています。
#
# 【イベントベース監視の利点】
# - メトリクスの遅延に依存しない
# - タスク停止の理由（OOM、DeploymentFailed等）が分かる
# - より詳細なトラブルシューティングが可能
#
# 【参考】
# ECS メトリクス監視とイベント監視の使い分け:
# - メトリクス: 継続的な状態監視（CPU、メモリ等）
# - イベント: 状態変化の検知（タスク起動/停止等）
# ============================================================
# resource "datadog_monitor" "ecs_tasks" {
#   count   = 0 # 無効化
#   name    = "[L1] ECS Desired Tasks"
#   type    = "metric alert"
#   query   = "avg(last_5m):sum:aws.ecs.service.desired{*} <= ${var.ecs_tasks_threshold}"
#   message = <<-EOT
#     [L1] ECS Clusterでタスクが0になりました。
#     - Cluster: ${var.ecs_cluster_name}
#     - Running Tasks: {{value}}
#     - 影響: 全テナント（サービス停止）
#
#     ${join("\n", var.notification_channels)}
#   EOT
#
#   monitor_thresholds {
#     critical = var.ecs_tasks_threshold
#     warning  = 1
#   }
#
#   tags = concat(
#     ["layer:l1-compute", "resource:ecs", "severity:critical"],
#     [for k, v in var.tags : "${k}:${v}"]
#   )
#
#   notify_no_data    = false
#   renotify_interval = 0
# }
