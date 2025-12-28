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
  query   = "avg(last_5m):(avg:aws.rds.database_connections{dbinstanceidentifier:${var.rds_instance_id}} / avg:aws.rds.database_connections.max{dbinstanceidentifier:${var.rds_instance_id}}) * 100 > ${var.rds_conn_threshold}"
  message = <<-EOT
    [L0] RDS 接続数が${var.rds_conn_threshold}%を超えました。
    - DB: ${var.rds_instance_id}
    - 接続数: {{value}}%
    - 影響: 全テナント

    ${join("\n", var.notification_channels)}
  EOT

  monitor_thresholds {
    critical = var.rds_conn_threshold
    warning  = 70
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
resource "datadog_monitor" "rds_storage" {
  name    = "[L0] RDS ストレージ"
  type    = "metric alert"
  query   = "avg(last_5m):(avg:aws.rds.free_storage_space{dbinstanceidentifier:${var.rds_instance_id}} / avg:aws.rds.allocated_storage{dbinstanceidentifier:${var.rds_instance_id}}) * 100 < ${var.rds_storage_threshold}"
  message = <<-EOT
    [L0] RDS 空きストレージが${var.rds_storage_threshold}%を下回りました。
    - DB: ${var.rds_instance_id}
    - 空きストレージ: {{value}}%
    - 影響: 全テナント

    ${join("\n", var.notification_channels)}
  EOT

  monitor_thresholds {
    critical = var.rds_storage_threshold
    warning  = 10
  }

  tags = concat(
    ["layer:l0", "resource:rds", "severity:critical"],
    [for k, v in var.tags : "${k}:${v}"]
  )

  notify_no_data    = false
  renotify_interval = 0
}

# L0-ECS-Tasks Monitor
resource "datadog_monitor" "ecs_tasks" {
  name    = "[L0] ECS Running Tasks"
  type    = "metric alert"
  query   = "avg(last_5m):avg:aws.ecs.running_tasks_count{clustername:${var.ecs_cluster_name}} <= ${var.ecs_tasks_threshold}"
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

# L0-VPC-Flow Monitor
resource "datadog_monitor" "vpc_flow" {
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
resource "datadog_monitor" "agent" {
  name    = "[L0] Datadog Agent 死活"
  type    = "service check"
  query   = "\"datadog.agent.up\".over(\"*\").by(\"host\").last(2).count_by_status()"
  message = <<-EOT
    [L0] Datadog Agentが停止しました。
    - Host: {{host.name}}
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
