# level3-tenant モジュール
# L3 テナント監視 Monitor の作成（for_each 対応）
#
# 依存: monitors.tf, variables.tf, outputs.tf

terraform {
  required_providers {
    datadog = {
      source = "datadog/datadog"
    }
  }
}
