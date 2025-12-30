# level0-infra モジュール
# L0 インフラ監視 Monitor の作成
#
# 依存: monitors.tf, variables.tf, outputs.tf

terraform {
  required_providers {
    datadog = {
      source = "datadog/datadog"
    }
  }
}
