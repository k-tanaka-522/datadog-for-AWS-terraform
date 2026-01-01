# level1-compute モジュール
# L1 コンピュートリソース監視 Monitor の作成
#
# 依存: monitors.tf, variables.tf, outputs.tf

terraform {
  required_providers {
    datadog = {
      source = "datadog/datadog"
    }
  }
}
