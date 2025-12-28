# composite モジュール
# Composite Monitor の作成（L0/L2/L3の親子関係によるアラート抑制）
#
# 依存: composites.tf, variables.tf, outputs.tf

terraform {
  required_providers {
    datadog = {
      source = "datadog/datadog"
    }
  }
}
