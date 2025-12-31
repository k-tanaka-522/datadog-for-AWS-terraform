# dashboard.tf
# Datadog Dashboard for Multi-Tenant Monitoring PoC

resource "datadog_dashboard" "poc_overview" {
  title       = "Datadog PoC - マルチテナント監視ダッシュボード"
  description = "Datadog + AWS ECS マルチテナント監視 PoC の統合ダッシュボード"
  layout_type = "ordered"

  # ===== モニターサマリー =====
  widget {
    group_definition {
      title            = "📊 モニターステータス概要"
      layout_type      = "ordered"
      background_color = "vivid_blue"

      widget {
        manage_status_definition {
          title               = "全モニター状態"
          title_size          = "16"
          title_align         = "left"
          display_format      = "countsAndList"
          color_preference    = "text"
          hide_zero_counts    = false
          show_last_triggered = true
          show_priority       = false
          query               = "tag:project:datadog-poc"
          sort                = "status,asc"
          summary_type        = "monitors"
        }
      }
    }
  }

  # ===== L0 インフラ監視 =====
  widget {
    group_definition {
      title            = "🏗️ L0: インフラ監視（RDS / ECS基盤）"
      layout_type      = "ordered"
      background_color = "vivid_orange"

      # RDS CPU使用率
      widget {
        timeseries_definition {
          title          = "RDS CPU使用率"
          title_size     = "16"
          title_align    = "left"
          show_legend    = true
          legend_layout  = "auto"
          legend_columns = ["avg", "max", "value"]

          request {
            q            = "avg:aws.rds.cpuutilization{dbinstanceidentifier:${var.rds_instance_id}}"
            display_type = "line"
            style {
              palette    = "dog_classic"
              line_type  = "solid"
              line_width = "normal"
            }
          }

          marker {
            value        = "y = 80"
            display_type = "warning dashed"
            label        = "Warning: 80%"
          }
          marker {
            value        = "y = 95"
            display_type = "error dashed"
            label        = "Critical: 95%"
          }
        }
      }

      # RDS 接続数
      widget {
        timeseries_definition {
          title       = "RDS 接続数"
          title_size  = "16"
          title_align = "left"

          request {
            q            = "avg:aws.rds.database_connections{dbinstanceidentifier:${var.rds_instance_id}}"
            display_type = "bars"
            style {
              palette = "cool"
            }
          }
        }
      }

      # ECS タスク数
      widget {
        timeseries_definition {
          title       = "ECS Running Tasks"
          title_size  = "16"
          title_align = "left"

          request {
            q            = "sum:aws.ecs.service.running{cluster_name:${var.ecs_cluster_name}} by {service_name}"
            display_type = "line"
            style {
              palette = "green"
            }
          }
        }
      }
    }
  }

  # ===== L2 サービス監視 =====
  widget {
    group_definition {
      title            = "🔧 L2: サービス監視（ALB / ECS Service）"
      layout_type      = "ordered"
      background_color = "vivid_yellow"

      # ALB リクエスト数
      widget {
        timeseries_definition {
          title       = "ALB リクエスト数"
          title_size  = "16"
          title_align = "left"

          request {
            q            = "sum:aws.applicationelb.request_count{loadbalancer:app/datadog-poc-alb*}.as_count()"
            display_type = "bars"
            style {
              palette = "purple"
            }
          }
        }
      }

      # ALB レスポンスタイム
      widget {
        timeseries_definition {
          title       = "ALB 平均レスポンスタイム"
          title_size  = "16"
          title_align = "left"

          request {
            q            = "avg:aws.applicationelb.target_response_time.average{loadbalancer:app/datadog-poc-alb*}"
            display_type = "line"
            style {
              palette = "warm"
            }
          }

          marker {
            value        = "y = 1"
            display_type = "warning dashed"
            label        = "Warning: 1s"
          }
        }
      }

      # ALB 5xx エラー
      widget {
        timeseries_definition {
          title       = "ALB 5xx エラー数"
          title_size  = "16"
          title_align = "left"

          request {
            q            = "sum:aws.applicationelb.httpcode_target_5xx{loadbalancer:app/datadog-poc-alb*}.as_count()"
            display_type = "bars"
            style {
              palette = "red"
            }
          }
        }
      }

      # ALB ターゲットヘルス
      widget {
        timeseries_definition {
          title       = "ALB Healthy/Unhealthy ターゲット"
          title_size  = "16"
          title_align = "left"

          request {
            q            = "sum:aws.applicationelb.healthy_host_count{loadbalancer:app/datadog-poc-alb*} by {targetgroup}"
            display_type = "line"
            style {
              palette = "green"
            }
          }
          request {
            q            = "sum:aws.applicationelb.un_healthy_host_count{loadbalancer:app/datadog-poc-alb*} by {targetgroup}"
            display_type = "line"
            style {
              palette = "red"
            }
          }
        }
      }
    }
  }

  # ===== L3 テナント監視 =====
  widget {
    group_definition {
      title            = "👥 L3: テナント別監視"
      layout_type      = "ordered"
      background_color = "vivid_green"

      # テナント別リクエスト数
      widget {
        timeseries_definition {
          title       = "テナント別リクエスト数"
          title_size  = "16"
          title_align = "left"

          request {
            q            = "sum:trace.fastapi.request.hits{service:demo-api-*} by {service}.as_count()"
            display_type = "bars"
            style {
              palette = "classic"
            }
          }
        }
      }

      # テナント別エラー率
      widget {
        timeseries_definition {
          title       = "テナント別エラー率 (%)"
          title_size  = "16"
          title_align = "left"

          request {
            q            = "sum:trace.fastapi.request.errors{service:demo-api-*} by {service}.as_count() / sum:trace.fastapi.request.hits{service:demo-api-*} by {service}.as_count() * 100"
            display_type = "line"
            style {
              palette = "red"
            }
          }

          marker {
            value        = "y = 1"
            display_type = "warning dashed"
            label        = "Warning: 1%"
          }
          marker {
            value        = "y = 5"
            display_type = "error dashed"
            label        = "Critical: 5%"
          }
        }
      }

      # テナント別レイテンシ（p99）
      widget {
        timeseries_definition {
          title       = "テナント別レイテンシ (p99)"
          title_size  = "16"
          title_align = "left"

          request {
            q            = "p99:trace.fastapi.request{service:demo-api-*} by {service}"
            display_type = "line"
            style {
              palette = "orange"
            }
          }

          marker {
            value        = "y = 1000000000"
            display_type = "warning dashed"
            label        = "Warning: 1s"
          }
          marker {
            value        = "y = 2000000000"
            display_type = "error dashed"
            label        = "Critical: 2s"
          }
        }
      }
    }
  }

  # ===== APM トレース =====
  widget {
    group_definition {
      title            = "📈 APM トレース"
      layout_type      = "ordered"
      background_color = "vivid_purple"

      # トップエラー
      widget {
        toplist_definition {
          title       = "エラートップ10（リソース別）"
          title_size  = "16"
          title_align = "left"

          request {
            q = "top(sum:trace.fastapi.request.errors{*} by {resource_name}.as_count(), 10, 'sum', 'desc')"
          }
        }
      }

      # トップ遅延
      widget {
        toplist_definition {
          title       = "遅延トップ10（リソース別）"
          title_size  = "16"
          title_align = "left"

          request {
            q = "top(p99:trace.fastapi.request{*} by {resource_name}, 10, 'max', 'desc')"
          }
        }
      }
    }
  }

  # ===== クイックリンク =====
  widget {
    note_definition {
      content          = <<-EOT
## 🔗 クイックリンク

### ヘルスチェックURL
- **tenant-a**: [http://${var.alb_fqdn}/tenant-a/health](http://${var.alb_fqdn}/tenant-a/health)
- **tenant-b**: [http://${var.alb_fqdn}/tenant-b/health](http://${var.alb_fqdn}/tenant-b/health)
- **tenant-c**: [http://${var.alb_fqdn}/tenant-c/health](http://${var.alb_fqdn}/tenant-c/health)

### テスト用API
- **エラーシミュレーション**: `POST /{tenant_id}/simulate/error`
- **レイテンシシミュレーション**: `POST /{tenant_id}/simulate/latency`

### Terraform管理
- **Project**: datadog-poc
- **Environment**: poc
- **Managed by**: Terraform
EOT
      background_color = "gray"
      font_size        = "14"
      text_align       = "left"
      show_tick        = false
      tick_pos         = "50%"
      tick_edge        = "left"
    }
  }

  tags = ["team:sre"]
}

output "dashboard_url" {
  description = "Datadog Dashboard URL"
  value       = "https://app.datadoghq.com/dashboard/${datadog_dashboard.poc_overview.id}"
}
