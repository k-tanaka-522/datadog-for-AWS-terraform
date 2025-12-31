# level2-service モジュール Monitor定義
# L2 サービス監視 Monitor（4個）

# L2-ALB-Health Monitor
# NOTE: 実際のTarget Group名は demo-api-tenant-*-tg 形式。
#       ワイルドカードで全テナントのTarget Groupを集計監視。
#       Datadog タグ形式: targetgroup:targetgroup/demo-api-tenant-X-tg/xxxx
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

# L2-ECS-Task Monitor（Event Monitor）
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

# L2-ECR-Vuln Monitor (disabled - requires ECR vulnerability scanning)
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

# FR-002-5: ALB→API→RDS E2Eヘルスチェック（Synthetics Test）
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
