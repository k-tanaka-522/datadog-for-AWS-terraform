# level0-infra モジュール Monitor定義
# L0 インフラ監視 Monitor（7個）

# L0-RDS-CPU Monitor
resource "datadog_monitor" "rds_cpu" {
  name    = "[L0] RDS CPU使用率"
  type    = "metric alert"
  query   = "avg(last_5m):avg:aws.rds.cpuutilization{dbinstanceidentifier:${var.rds_instance_id}} > ${var.rds_cpu_threshold}"
  message = <<-EOT
    [L0] RDS CPU使用率が${var.rds_cpu_threshold}%を超えました。
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
    ["layer:l0", "resource:rds", "severity:critical"],
    [for k, v in var.tags : "${k}:${v}"]
  )

  notify_no_data    = false
  renotify_interval = 0
}

# L0-RDS-Conn Monitor
resource "datadog_monitor" "rds_conn" {
  name    = "[L0] RDS 接続数"
  type    = "metric alert"
  query   = "avg(last_5m):avg:aws.rds.database_connections{dbinstanceidentifier:${var.rds_instance_id}} > ${var.rds_conn_threshold}"
  message = <<-EOT
    [L0] RDS 接続数が${var.rds_conn_threshold}を超えました。
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
    ["layer:l0", "resource:rds", "severity:critical"],
    [for k, v in var.tags : "${k}:${v}"]
  )

  notify_no_data    = false
  renotify_interval = 0
}

# L0-RDS-Mem Monitor
resource "datadog_monitor" "rds_mem" {
  name    = "[L0] RDS 空きメモリ"
  type    = "metric alert"
  query   = "avg(last_5m):avg:aws.rds.freeable_memory{dbinstanceidentifier:${var.rds_instance_id}} < ${var.rds_mem_threshold}"
  message = <<-EOT
    [L0] RDS 空きメモリが${var.rds_mem_threshold}バイト（${floor(var.rds_mem_threshold / 1073741824)}GB）を下回りました。
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
    ["layer:l0", "resource:rds", "severity:critical"],
    [for k, v in var.tags : "${k}:${v}"]
  )

  notify_no_data    = false
  renotify_interval = 0
}

# L0-RDS-Storage Monitor
# NOTE: CloudWatch/Datadog には total_storage_space メトリクスがないため、
#       絶対値（バイト）での監視に変更。5GB以下でアラート、10GB以下で警告。
resource "datadog_monitor" "rds_storage" {
  name    = "[L0] RDS 空きストレージ"
  type    = "metric alert"
  query   = "avg(last_5m):avg:aws.rds.free_storage_space{dbinstanceidentifier:${var.rds_instance_id}} < ${var.rds_storage_threshold_bytes}"
  message = <<-EOT
    [L0] RDS 空きストレージが${floor(var.rds_storage_threshold_bytes / 1073741824)}GBを下回りました。
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
    ["layer:l0", "resource:rds", "severity:critical"],
    [for k, v in var.tags : "${k}:${v}"]
  )

  notify_no_data    = false
  renotify_interval = 0
}

# L0-ECS-Tasks Monitor
# NOTE: aws.ecs.service.desired は ECS サービスの desired count。
#       running が取得できない場合の代替。0 以下でアラート。
resource "datadog_monitor" "ecs_tasks" {
  name    = "[L0] ECS Desired Tasks"
  type    = "metric alert"
  query   = "avg(last_5m):sum:aws.ecs.service.desired{*} <= ${var.ecs_tasks_threshold}"
  message = <<-EOT
    [L0] ECS Clusterでタスクが0になりました。
    - Cluster: ${var.ecs_cluster_name}
    - Running Tasks: {{value}}
    - 影響: 全テナント（サービス停止）

    ${join("\n", var.notification_channels)}
  EOT

  monitor_thresholds {
    critical = var.ecs_tasks_threshold
    warning  = 1
  }

  tags = concat(
    ["layer:l0", "resource:ecs", "severity:critical"],
    [for k, v in var.tags : "${k}:${v}"]
  )

  notify_no_data    = false
  renotify_interval = 0
}

# L0-VPC-Flow Monitor (disabled - requires Log Management enabled)
resource "datadog_monitor" "vpc_flow" {
  count   = 0 # Disabled: Log Management not enabled in this Datadog account
  name    = "[L0] VPC Flow Logs 異常"
  type    = "log alert"
  query   = "logs(\"source:vpc-flow-logs status:reject\").rollup(\"count\").last(\"5m\") > 100"
  message = <<-EOT
    [L0] VPC Flow Logsで異常なトラフィックを検知しました。
    - Rejected Packets: {{value}}
    - 影響: 全テナント

    ${join("\n", var.notification_channels)}
  EOT

  monitor_thresholds {
    critical = 100
    warning  = 50
  }

  tags = concat(
    ["layer:l0", "resource:vpc", "severity:high"],
    [for k, v in var.tags : "${k}:${v}"]
  )

  notify_no_data    = false
  renotify_interval = 0
}

# L0-Agent Monitor
# NOTE: ECS Fargate ではサイドカーとして Agent が動作。
#       Fargate のホスト名は動的に変わり、service check のタグ付けが異なる。
#       ワイルドカードで env:poc タグを使用して Agent 監視。
resource "datadog_monitor" "agent" {
  name    = "[L0] Datadog Agent 死活"
  type    = "service check"
  query   = "\"datadog.agent.up\".over(\"env:poc\").by(\"host\").last(2).count_by_status()"
  message = <<-EOT
    [L0] Datadog Agentが停止しました。
    - Host: {{host.name}}
    - Cluster: ${var.ecs_cluster_name}
    - 影響: 該当ホストの監視停止

    ${join("\n", var.notification_channels)}
  EOT

  monitor_thresholds {
    critical = 1
    ok       = 1
  }

  tags = concat(
    ["layer:l0", "resource:agent", "severity:critical"],
    [for k, v in var.tags : "${k}:${v}"]
  )

  notify_no_data    = true
  no_data_timeframe = 10
  renotify_interval = 0
}
