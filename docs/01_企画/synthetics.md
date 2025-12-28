# Datadog Synthetics

## 概要

Datadog Synthetics は外形監視 (Synthetic Monitoring) サービス。
世界各地のロケーションから定期的に API やブラウザテストを実行し、サービスの可用性とパフォーマンスを監視する。

## 本プロジェクトでの使用

Level 2 のテナント別ヘルスチェックに使用:

```
Datadog Synthetics
    │
    │ 1分間隔で実行
    ▼
https://alb-dns/acme/health
https://alb-dns/globex/health
    │
    │ 200 OK? レスポンスタイム?
    ▼
Monitor として評価 → Composite Monitor へ
```

## テストタイプ

### API Test (本プロジェクトで使用)

HTTP/HTTPS エンドポイントを監視:

```hcl
resource "datadog_synthetics_test" "health" {
  name    = "[L2] acme Health Check"
  type    = "api"        # API Test
  subtype = "http"       # HTTP サブタイプ

  request_definition {
    method = "GET"
    url    = "https://example.com/acme/health"
  }

  assertion {
    type     = "statusCode"
    operator = "is"
    target   = "200"
  }

  assertion {
    type     = "responseTime"
    operator = "lessThan"
    target   = 5000  # 5秒以内
  }
}
```

### Browser Test (今回は未使用)

実際のブラウザでユーザー操作をシミュレート:
- ログインフロー
- フォーム送信
- 画面遷移

### Multistep API Test (今回は未使用)

複数の API を順番に呼び出し:
- 認証 → API 呼び出し → 結果検証

## ロケーション

テストを実行する地理的な場所:

```hcl
locations = [
  "aws:ap-northeast-1",  # 東京
  # 必要に応じて追加
  # "aws:ap-southeast-1",  # シンガポール
  # "aws:us-east-1",       # バージニア
]
```

### 利用可能なロケーション (抜粋)

| リージョン | ロケーション ID |
|-----------|-----------------|
| 東京 | aws:ap-northeast-1 |
| 大阪 | aws:ap-northeast-3 |
| シンガポール | aws:ap-southeast-1 |
| シドニー | aws:ap-southeast-2 |
| バージニア | aws:us-east-1 |
| オレゴン | aws:us-west-2 |
| フランクフルト | aws:eu-central-1 |

## オプション設定

```hcl
options_list {
  # 実行間隔 (秒)
  tick_every = 60  # 1分間隔

  # リトライ設定
  retry {
    count    = 2    # 失敗時に2回リトライ
    interval = 300  # 300ミリ秒間隔
  }

  # 失敗判定
  min_failure_duration = 0  # 即座に失敗判定
  min_location_failed  = 1  # 1ロケーション失敗で失敗判定

  # アラート設定
  monitor_options {
    renotify_interval = 60  # 60分ごとに再通知
  }
}
```

## Assertion (検証条件)

### ステータスコード

```hcl
assertion {
  type     = "statusCode"
  operator = "is"
  target   = "200"
}
```

### レスポンスタイム

```hcl
assertion {
  type     = "responseTime"
  operator = "lessThan"
  target   = 5000  # 5000ms = 5秒
}
```

### レスポンスボディ

```hcl
assertion {
  type     = "body"
  operator = "contains"
  target   = "\"status\":\"ok\""
}
```

### ヘッダー

```hcl
assertion {
  type     = "header"
  property = "content-type"
  operator = "contains"
  target   = "application/json"
}
```

## 認証が必要な場合

### Basic 認証

```hcl
request_basicauth {
  username = "user"
  password = "pass"  # 本番では変数化
}
```

### ヘッダー認証

```hcl
request_headers = {
  Authorization = "Bearer ${var.api_token}"
}
```

## Composite Monitor との連携

Synthetics Test は自動的に Monitor を生成:

```hcl
# Synthetics Test
resource "datadog_synthetics_test" "health" {
  name = "[L2] acme Health Check"
  # ...
}

# 生成された Monitor ID を参照
output "monitor_id" {
  value = datadog_synthetics_test.health.monitor_id
}

# Composite Monitor で使用
resource "datadog_monitor" "composite" {
  type  = "composite"
  query = "!${datadog_synthetics_test.health.monitor_id} && ${other_monitor_id}"
}
```

## フリープランの制限

Datadog のプランによって Synthetics の利用に制限がある:

| プラン | API Test | Browser Test | 実行回数 |
|--------|----------|--------------|----------|
| Free | 制限あり | 不可 | 制限あり |
| Pro | 可 | 可 | プランによる |
| Enterprise | 可 | 可 | プランによる |

### フリープランでの代替案

Synthetics が使えない場合、ALB の Target Group ヘルスチェックで代用:

```hcl
# Target Group の HealthyHostCount を監視
resource "datadog_monitor" "tg_health" {
  for_each = var.tenants

  name = "[L2] ${each.key} TG Health"
  type = "metric alert"

  query = "avg(last_5m):avg:aws.applicationelb.healthy_host_count{targetgroup:${each.value.tg_arn_suffix}} < 1"
}
```

## トラブルシューティング

### テストが失敗する

1. **ネットワーク問題**
   - Security Group で Datadog IP を許可しているか確認
   - [Datadog IP Ranges](https://docs.datadoghq.com/api/latest/ip-ranges/)

2. **SSL 証明書エラー**
   - 自己署名証明書の場合、検証をスキップ:
   ```hcl
   request_definition {
     no_saving_response_body = false
     allow_insecure          = true  # 本番では非推奨
   }
   ```

3. **タイムアウト**
   - `timeout` オプションを調整

### メトリクスが見えない

- `synthetics.api.response_time` などのメトリクスは Pro プラン以上
- Monitor のステータスは全プランで利用可能

## 参考リンク

- [Datadog Synthetics ドキュメント](https://docs.datadoghq.com/synthetics/)
- [Terraform datadog_synthetics_test](https://registry.terraform.io/providers/DataDog/datadog/latest/docs/resources/synthetics_test)
- [Synthetics API テスト](https://docs.datadoghq.com/synthetics/api_tests/)
