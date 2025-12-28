# 監視設計 (Composite Monitor)

## 概要

本プロジェクトでは、Datadog の Composite Monitor を使用して監視を階層化する。
これにより、インフラ障害時にアプリケーションレベルのアラートが大量発報される「アラートストーム」を防止する。

## 階層構造

```
Level 0: インフラ基盤
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
│
├── RDS
│    ├── CPU > 95%
│    ├── Connections > 90%
│    ├── FreeableMemory < 256MB
│    └── FreeStorageSpace < 2GB
│
└── ECS Cluster
     └── Running Tasks = 0

        │
        │ L0 が全て OK なら
        ▼

Level 2: テナント別ヘルスチェック
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
│
├── [acme] /acme/health → 200
├── [globex] /globex/health → 200
└── [newcorp] /newcorp/health → 200

        │
        │ 該当テナントの L2 が OK なら
        ▼

Level 3: テナント別詳細監視
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
│
├── [acme]
│    ├── Error Log Count > 10/5min
│    ├── Latency p99 > 500ms
│    └── Error Rate > 5%
│
├── [globex]
│    └── ...
│
└── [newcorp]
     └── ...
```

## 抑制の仕組み

### Composite Monitor とは

複数のモニターを論理演算子 (AND/OR/NOT) で組み合わせた条件式。
条件を満たした場合のみアラートを発火させる。

```hcl
# 例: RDSがOK かつ ヘルスがOK かつ エラーログがALERT
query = "!${rds_monitor_id} && !${health_monitor_id} && ${error_log_monitor_id}"
```

### 抑制パターン

#### パターン1: RDS 障害

```
発生: RDS CPU 100%

  [L0] RDS CPU → ALERT 🔔 (通知される)
       ↓ 抑制
  [L2] Health → (評価されない)
       ↓ 抑制
  [L3] Error Logs → (評価されない)

結果: 1件のアラートのみ
```

#### パターン2: 特定テナントのバグ

```
発生: acme テナントで NullPointerException

  [L0] RDS → OK
  [L0] ECS → OK
       ↓
  [L2] acme Health → ALERT 🔔 (通知される)
  [L2] globex Health → OK
       ↓
  [L3] acme Error Logs → ALERT 🔔 (通知される、調査用)
  [L3] globex Error Logs → (評価される、問題なければOK)

結果: acme のみ通知、globex には影響なし
```

#### パターン3: 一時的なスパイク

```
発生: acme で一時的に Latency 上昇

  [L0] RDS → OK
  [L0] ECS → OK
       ↓
  [L2] acme Health → OK (200は返している)
       ↓
  [L3] acme Latency → ALERT 🔔 (通知される)

結果: レイテンシアラートのみ通知
```

## 実装

### Level 0: インフラ基盤

```hcl
# modules/level0-infra/rds.tf

resource "datadog_monitor" "rds_cpu" {
  name    = "[L0] RDS CPU Critical"
  type    = "metric alert"
  
  query   = "avg(last_5m):avg:aws.rds.cpuutilization{dbinstanceidentifier:${var.rds_identifier}} > 95"
  
  message = <<-EOT
    ## RDS CPU 過負荷
    
    全テナントに影響の可能性があります。
    
    対応:
    1. スロークエリの確認
    2. 接続数の確認
    3. 必要に応じてスケールアップ
    
    @slack-alerts-critical
  EOT

  tags = ["level:0", "resource:rds", "severity:critical"]
}
```

### Level 2: テナント別ヘルスチェック

```hcl
# modules/level2-health/synthetics.tf

resource "datadog_synthetics_test" "health" {
  for_each = var.tenants

  name    = "[L2] ${each.key} Health Check"
  type    = "api"
  subtype = "http"
  status  = "live"

  request_definition {
    method = "GET"
    url    = "https://${var.alb_dns}${each.value.health_path}"
  }

  assertion {
    type     = "statusCode"
    operator = "is"
    target   = "200"
  }

  assertion {
    type     = "responseTime"
    operator = "lessThan"
    target   = 5000
  }

  locations = ["aws:ap-northeast-1"]
  
  options_list {
    tick_every = 60
    
    retry {
      count    = 2
      interval = 300
    }
  }

  message = <<-EOT
    ## ${each.key} ヘルスチェック失敗
    
    エンドポイント: ${each.value.health_path}
    
    @slack-${each.value.slack_channel}
  EOT

  tags = ["level:2", "tenant:${each.key}"]
}
```

### Level 3: テナント別詳細

```hcl
# modules/level3-tenant/logs.tf

resource "datadog_monitor" "error_logs" {
  name = "[L3] ${var.tenant_id} Error Logs"
  type = "log alert"

  query = <<-EOT
    logs("service:demo-api @tenant_id:${var.tenant_id} status:error")
    .index("*")
    .rollup("count")
    .last("5m") > ${var.config.error_log_threshold}
  EOT

  message = <<-EOT
    ## ${var.tenant_id} エラーログ増加
    
    5分間のエラーログ数が閾値を超えました。
    
    ログ確認:
    https://app.datadoghq.com/logs?query=service:demo-api @tenant_id:${var.tenant_id} status:error
    
    @slack-${var.config.slack_channel}
  EOT

  tags = ["level:3", "tenant:${var.tenant_id}", "type:logs"]
}
```

### Composite Monitor

```hcl
# modules/composite/main.tf

locals {
  # L0が全部OKの条件 (NOT で反転)
  l0_ok = join(" && ", [for id in var.level0_monitor_ids : "!${id}"])
  
  # L2がOKの条件
  l2_ok = "!${var.level2_monitor_id}"
  
  # L3のどれかがALERT
  l3_alert = join(" || ", var.level3_monitor_ids)
}

resource "datadog_monitor" "composite" {
  name = "[Composite] ${var.tenant_id}"
  type = "composite"

  # 条件: L0がOK かつ L2がOK かつ L3がALERT
  query = "(${local.l0_ok}) && (${local.l2_ok}) && (${local.l3_alert})"

  message = <<-EOT
    ## ${var.tenant_id} アプリケーションアラート
    
    ✓ インフラ基盤 (L0): 正常
    ✓ ヘルスチェック (L2): 正常
    ✗ 詳細監視 (L3): 異常検知
    
    → アプリケーション起因の可能性が高い
    
    @slack-${var.slack_channel}
  EOT

  tags = ["composite:true", "tenant:${var.tenant_id}"]
}
```

## 通知先の設計

```
Level 0 (インフラ)
├── 即座に通知
├── 宛先: #alerts-critical (全員)
└── PagerDuty 連携推奨

Level 2 (ヘルス)
├── 即座に通知
├── 宛先: #alerts-{tenant} (担当者)
└── リトライ後に通知

Level 3 (詳細)
├── Composite 経由で通知
├── 宛先: #alerts-{tenant}-detail
└── 調査用情報を含める
```

## タグ設計

すべてのモニターに以下のタグを付与:

| タグ | 値 | 用途 |
|-----|-----|-----|
| `level` | 0, 2, 3 | 階層識別 |
| `tenant` | acme, globex, ... | テナント識別 |
| `resource` | rds, ecs, alb | リソース種別 |
| `type` | logs, metrics, synthetics | 監視種別 |
| `severity` | critical, warning, info | 重要度 |
| `composite` | true | Composite Monitor フラグ |

ダッシュボードやアラート検索で使用:

```
# Level 0 のモニター一覧
level:0

# acme テナントの全モニター
tenant:acme

# 全テナントのログ監視
type:logs level:3
```

## ベストプラクティス

### 1. ヘルスチェックは DB 疎通まで確認

```python
@app.get("/{tenant_id}/health")
async def health(tenant_id: str):
    # DBへのクエリを実行して疎通確認
    await db.execute(f"SELECT 1 FROM {tenant_id}.health_check")
    return {"status": "ok", "tenant": tenant_id}
```

### 2. 閾値は段階的に調整

初期値は緩めに設定し、運用しながら調整:

```hcl
# 初期設定 (緩め)
error_log_threshold   = 50
latency_p99_threshold = 2000

# 運用後 (厳しく)
error_log_threshold   = 10
latency_p99_threshold = 500
```

### 3. 親子関係は依存関係に沿う

```
依存関係:
  App → DB
  App → Network

監視の親子:
  DB監視 (親) → App監視 (子)
  Network監視 (親) → App監視 (子)
```

### 4. Composite の条件式はシンプルに

複雑な条件式はデバッグが困難:

```hcl
# NG: 複雑すぎる
query = "(A && B) || (C && !D) && (E || F)"

# OK: シンプルに
query = "!parent_ok && child_alert"
```
