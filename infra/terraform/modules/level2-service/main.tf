# level2-service モジュール
# L2 サービス監視 Monitor の作成
#
# 依存: monitors.tf, variables.tf, outputs.tf

terraform {
  required_providers {
    datadog = {
      source = "datadog/datadog"
    }
  }
}
