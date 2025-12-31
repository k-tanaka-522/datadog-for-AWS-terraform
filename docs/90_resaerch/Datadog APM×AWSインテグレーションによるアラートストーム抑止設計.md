# Datadog APM×AWSインテグレーションによるアラートストーム抑止設計

## 結論：依存関係を活用したレイヤー別監視と自動抑制が鍵

Datadog APMとAWSインテグレーションを組み合わせたAWS監視では、**Composite Monitor による複合条件アラート**、**Webhook+Downtime APIによる依存関係ベースの自動抑制**、**統一タグによるレイヤー間相関**の3つが、アラートストーム防止の核心となる。APMはECSなどアプリケーションレイヤーのトレースベース監視に、AWSインテグレーションはALB/RDSなどマネージドサービスの基盤監視に使い分けることで、**70〜90%のアラート削減**が実現可能である。

---

## APMによる監視設計：ECSでの分散トレーシング活用

### ECS Fargateでのセットアップパターン

Datadog AgentをECSで利用する場合、Fargateでは**サイドカーコンテナ**として各タスク定義に追加する必要がある。EC2起動タイプでは**デーモンサービス**として各インスタンスに1つのAgentをデプロイする。

**Fargateサイドカー設定の必須環境変数：**
- `DD_APM_ENABLED=true` - APMトレーシングの有効化
- `DD_APM_NON_LOCAL_TRAFFIC=true` - 他コンテナからのトレース受信許可
- `ECS_FARGATE=true` - Fargate環境識別

アプリケーションコンテナ側では**Unified Service Tagging**（`DD_SERVICE`、`DD_ENV`、`DD_VERSION`）を設定することで、サービスマップでの自動依存関係検出とバージョン別のパフォーマンス追跡が可能になる。

### APMトレースベースのアラート設計

APMでは以下の**4種類のモニタータイプ**が利用可能である：

| モニタータイプ | 用途 | 推奨シナリオ |
|---------------|------|-------------|
| APM Monitor | サービス/リソース単位の閾値アラート | 標準的なSLI監視 |
| Trace Analytics | カスタムファセットによる複雑なスパンクエリ | 特定エンドポイント監視 |
| Anomaly Monitor | 過去パターンからの逸脱検知 | トラフィック変動が大きい環境 |
| Composite Monitor | 複数条件のブール論理結合 | ノイズ削減・誤検知防止 |

**推奨メトリクスと閾値の目安：**
- **p95レイテンシ**：Warning 500ms / Critical 1000ms
- **エラーレート**：Warning 1% / Critical 5%
- **スループット低下**：ベースライン比 -30%（Warning）/ -50%（Critical）

トレースからの自動依存関係検出は**Agent v7.60以上**で利用可能な「Inferred Services」機能により、データベース・キュー・外部APIへのアウトバウンドリクエストから自動的に依存先を発見する。

### アラートノイズ削減のための設定パターン

APMアラートで誤検知を減らすための**5つの重要設定**がある：

1. **評価ウィンドウの拡大**：15分以上の評価期間で一時的スパイクをフィルタリング
2. **Recovery Threshold**：アラート閾値80%、回復閾値70%のように差をつけ、フラッピング防止
3. **Composite Monitor活用**：「エラーレート > 3% AND リクエスト数 > 100/30分」のように低トラフィック時の誤検知を排除
4. **通知グルーピング**：ホスト単位ではなくサービス単位でグループ化し、通知量を大幅削減
5. **条件変数による動的ルーティング**：`{{#is_exact_match}}`を使い、クラスタやサービスごとに通知先を振り分け

---

## AWSインテグレーションによる監視設計：CloudWatchメトリクスの活用

### データ収集の仕組みと遅延特性

AWSインテグレーションは**2つの収集方式**を提供している：

| 方式 | 遅延 | 特徴 |
|------|------|------|
| API Polling（デフォルト） | **15〜20分** | 設定簡単、GetMetricData API利用 |
| CloudWatch Metric Streams | **2〜3分** | Firehose経由、リアルタイム性重視 |

クリティカルなサービス（ALB、Lambda）には**Metric Streams**を推奨する。API Pollingを使う場合は、アラートの**評価遅延を300〜900秒**（5〜15分）に設定し、データ到着前の誤検知を防ぐ必要がある。

### ALB監視の重要メトリクス

ALB（Application Load Balancer）はAPMでのトレーシングが不可能なため、CloudWatchメトリクスベースの監視が必須となる：

| メトリクス | 意味 | アラート推奨 |
|-----------|------|-------------|
| `aws.applicationelb.healthy_host_count` | 正常なターゲット数 | 最小必要数を下回ったら即時アラート |
| `aws.applicationelb.unhealthy_host_count` | 異常ターゲット数 | **> 0** で即時アラート |
| `aws.applicationelb.httpcode_elb_5xx` | LB自体の5XXエラー | 発生時点で即時調査 |
| `aws.applicationelb.target_response_time` | バックエンドレイテンシ | p95/p99がSLA超過で警告 |
| `aws.applicationelb.httpcode_target_5xx` | バックエンドの5XXエラー | ベースライン超過で警告 |

**5XXエラーコードの意味**も理解しておく必要がある：502（Bad Gateway）はバックエンドの不正レスポンス、503（Service Unavailable）はキャパシティ不足または全ホスト異常、504（Gateway Timeout）はアイドルタイムアウト超過を示す。

### RDS・ElastiCache監視のポイント

**RDSの3階層監視**：
1. **Standard Integration**：CPU、接続数、ストレージ（10分間隔）
2. **Enhanced Monitoring**：50以上のシステムレベルメトリクス（最短1秒間隔）
3. **Database Monitoring（DBM）**：クエリ分析、Explainプラン、スキーマ情報

**RDSの重要アラート閾値**：
- `aws.rds.cpuutilization` > 85%（15分継続）
- `aws.rds.database_connections` が max_connections の80%に到達
- `aws.rds.replica_lag` > 30秒
- `aws.rds.free_storage_space` < 10%

**ElastiCacheでは eviction（退避）が発生したら即座に警告**が必要で、これはメモリ圧迫の明確なサインである。

---

## アラートストーム抑止の具体的手法

### Composite Monitorによる複合条件アラート

Composite Monitorは**最大10個の既存モニターをブール論理で結合**し、複数条件が同時に満たされた場合のみアラートを発生させる。

**構文と演算子：**
```
&&（AND）：両条件が真
||（OR）：いずれかが真
! （NOT）：否定
()：優先順位指定
```

**実践的なパターン例：**

1. **低トラフィック時の誤検知排除**
```
(error_rate > 3%) && (request_count > 100)
```
トラフィックが少ない時間帯の偶発的エラーでアラートが鳴らない。

2. **サービス再起動中のノイズ除去**
```
!service_uptime_alert && queue_length_alert
```
サービス kind起動中（uptimeアラート発生中）はキュー長アラートを抑制。

3. **持続的エラーの検出**
```
realtime_metric_alert && timeshifted_metric_alert
```
同じメトリクスの現在値と過去X分の値の両方が異常な場合のみアラート。

### Webhook + Downtime APIによる依存関係ベース抑制

Datadogにはネイティブの「アラートツリー」機能がないため、**Webhook通知とDowntime APIの組み合わせ**で実装する：

**設定手順：**
1. 上流モニター（例：RDS可用性）のアラートメッセージに`@webhook-mute-dependents`を追加
2. Webhookが発火時にDowntime APIを呼び出し、依存サービスをスコープでミュート
3. 回復時に`@webhook-unmute-dependents`で自動的にミュート解除

**アラートメッセージ設定例：**
```markdown
{{#is_alert}}
RDS {{availability-zone.name}} が停止しました
依存するすべてのサービスアラートを自動ミュートします
@webhook-mute-dependent-monitors
{{/is_alert}}

{{#is_alert_recovery}}
RDS {{availability-zone.name}} が復旧しました
依存サービスのミュートを解除します
@webhook-unmute-dependent-monitors
{{/is_alert_recovery}}
```

### Monitor Downtimeによる計画的抑制

**3つの主要ユースケース：**

1. **メンテナンスウィンドウ**：定期的なパッチ適用時間帯をRRULEで繰り返し設定
2. **デプロイメント時**：CI/CDパイプラインからAPI経由でアドホックダウンタイムを作成
3. **営業時間外**：非営業時間の低優先度アラートを自動ミュート

**スコープ指定の例：**
```json
{
  "scope": "env:prod AND service:web-store",
  "message": "メンテナンスによる計画停止"
}
```

**自動ミュート機能**も活用可能で、DatadogはAWS EC2、Azure VM、GCEインスタンスの終了を検知して自動的にミュートする。オートスケーリングによるスケールインでも余計なアラートは発生しない。

### Alert Groupingによる通知集約

**Simple Alert**と**Multi-Alert**の使い分けが重要である：

- **Simple Alert**：すべてのデータを単一アラートに集約（通知は1件のみ）
- **Multi-Alert**：グループの組み合わせごとに個別通知（詳細な可視性）

**推奨グルーピング戦略：**
ホスト単位ではなく**サービス単位またはAZ単位**でグループ化することで、数百件のホストアラートを数件のサービスアラートに集約できる。

---

## APMとAWSインテグレーションを混合した監視アーキテクチャ

### レイヤー別ツール選択の判断基準

| レイヤー | 主要ツール | 補助ツール | 理由 |
|---------|-----------|-----------|------|
| **ALB** | AWSインテグレーション | なし | Agent不可、CloudWatchで十分 |
| **ECS（タスク）** | APM Agent | AWSインテグレーション | トレース必須、クラスタ全体像は Integration で補完 |
| **RDS** | AWSインテグレーション + DBM | なし | RDS上にAgent不可、リモートDBMで深い洞察 |
| **ElastiCache** | AWSインテグレーション | なし | マネージドサービス、CloudWatchのみ |
| **Lambda** | AWSインテグレーション | 拡張（トレーシング） | サーバーレス、Metric Streams推奨 |

### マルチレイヤーアーキテクチャ図

```
┌─────────────────────────────────────────────────────────────┐
│                    Datadog Platform                          │
│  ┌───────────┐  ┌───────────┐  ┌───────────┐  ┌───────────┐ │
│  │Service Map│  │APM Traces │  │Dashboards │  │ Monitors  │ │
│  └───────────┘  └───────────┘  └───────────┘  └───────────┘ │
└─────────────────────────┬───────────────────────────────────┘
                          │
    ┌─────────────────────┼─────────────────────┐
    │                     │                     │
    ▼                     ▼                     ▼
┌─────────────┐    ┌─────────────┐    ┌─────────────────┐
│     ALB     │    │    ECS      │    │      RDS        │
│ Integration │    │  APM Agent  │    │ Integration+DBM │
│    のみ     │    │ +Integration│    │                 │
└─────────────┘    └─────────────┘    └─────────────────┘
       │                  │                     │
       └──────────────────┼─────────────────────┘
                          │
                   CloudWatch API
```

### アラートフロー設計の原則

**上位レイヤー（ユーザー影響）を優先**しつつ、**下位レイヤー（根本原因）を抑制**するのが基本戦略である：

1. **ALBアラート**（最上位）：5XXエラー、レイテンシ悪化 → ユーザー影響を即座に検知
2. **ECSアラート**（中間層）：エラーレート、CPU/メモリ → アプリケーション問題を特定
3. **RDSアラート**（最下位）：接続枯渇、CPU高騰 → 根本原因を特定

**依存関係抑制のロジック**：RDSに問題がある場合、ECSとALBのアラートは自動的にミュートし、RDSアラートのみを通知する。これにより、1つの根本原因から発生する連鎖的なアラートストームを防ぐ。

---

## 実践的な設計例

### 例1：ECS（APM）+ ALB（Integration）の組み合わせ

**Step 1: AWSインテグレーション設定**
Terraformで IAMロールを作成し、ApplicationELB名前空間を有効化。

**Step 2: ECSタスク定義にDatadog Agentサイドカーを追加**
```json
{
  "containerDefinitions": [
    {
      "name": "datadog-agent",
      "image": "public.ecr.aws/datadog/agent:latest",
      "cpu": 256,
      "memory": 512,
      "portMappings": [{"containerPort": 8126}],
      "environment": [
        {"name": "DD_APM_ENABLED", "value": "true"},
        {"name": "DD_APM_NON_LOCAL_TRAFFIC", "value": "true"}
      ]
    },
    {
      "name": "api-service",
      "environment": [
        {"name": "DD_SERVICE", "value": "checkout-api"},
        {"name": "DD_ENV", "value": "production"}
      ]
    }
  ]
}
```

**Step 3: 相関ダッシュボード作成**
- ALBレイテンシ（`aws.applicationelb.target_response_time`）
- APM p99レイテンシ（`trace.web.request.duration`）
- デプロイイベントをオーバーレイ表示

### 例2：ALB → ECS → RDS のフルスタックアラートチェーン

**Composite Monitorによる統合アラート：**
```
構成モニター：
a = ALB 5xxエラー > 10件/分
b = ECSタスク再起動 > 3回/5分
c = RDS CPU > 90%
d = APMエラーレート > 5%

Composite条件: (a && d) || (b && c)
```

**Webhook依存関係による抑制設定：**

1. **RDSヘルスモニター**（Layer 3 - 最下位）
```yaml
name: "RDS接続プール監視"
query: "avg:aws.rds.database_connections{db:main} > 180"
message: |
  {{#is_alert}}
  @webhook-mute-rds-dependents
  {{/is_alert}}
  {{#is_alert_recovery}}
  @webhook-unmute-rds-dependents
  {{/is_alert_recovery}}
tags:
  - "layer:database"
  - "service:main-rds"
```

2. **ECSサービスモニター**（Layer 2 - 中間層）
```yaml
name: "APIサービスエラーレート"
query: "avg:trace.web.request.errors{service:api} > 0.05"
tags:
  - "layer:application"
  - "dependency:main-rds"  # ← RDSアラート時に自動ミュート対象
```

3. **ALBモニター**（Layer 1 - 最上位）
```yaml
name: "ALB 5XXエラー"
query: "sum:aws.applicationelb.httpcode_elb_5xx{name:prod-alb} > 0"
tags:
  - "layer:loadbalancer"
  - "dependency:api-service"
```

### 例3：タグベースの統一設計

**すべてのレイヤーで一貫したタグ付け**を行うことで、スコープ指定による一括操作が可能になる：

```yaml
# 共通タグ構造
tags:
  - "env:production"
  - "service:checkout"
  - "team:payments"
  - "layer:application|database|loadbalancer"
  - "dependency:<上流サービス名>"
```

これにより、`scope: service:checkout AND env:production`のような指定で、チェックアウトサービス全体のダウンタイムを一括設定できる。

---

## ベストプラクティス総括

### アラートノイズ削減チェックリスト

| 施策 | 効果 | 実装難易度 |
|------|------|-----------|
| **Composite Monitor** | 複合条件で誤検知70%削減 | 中 |
| **通知グルーピング** | ホスト→サービス単位で90%削減 | 低 |
| **評価ウィンドウ拡大** | 一時スパイクによる誤検知排除 | 低 |
| **Recovery Threshold** | フラッピング防止 | 低 |
| **Webhook依存関係抑制** | カスケード障害時の集約 | 高 |
| **Scheduled Downtime** | 計画作業時のゼロノイズ | 低 |
| **Metric Streams** | 遅延起因の誤検知削減 | 中 |

### 監視設計の優先順位

1. **依存関係マッピング先行**：Service Mapで全体像を把握してから設計開始
2. **上位レイヤー監視を厳格に**：ユーザー影響（ALB）は厳しい閾値、根本原因（RDS）は余裕を持たせる
3. **Unified Service Taggingの徹底**：`DD_SERVICE`/`DD_ENV`/`DD_VERSION`をすべてのサービスで統一
4. **定期レビュー**：Monitor Notifications Overviewダッシュボードで月次レビュー、ノイジーなアラートを特定・調整

---

## 結論

Datadog APMとAWSインテグレーションを効果的に組み合わせるには、**レイヤーごとの適切なツール選択**と**依存関係を考慮した抑制設計**が不可欠である。APMはECSなどアプリケーションコード実行環境のトレーシングに、AWSインテグレーションはALB・RDSなどマネージドサービスの基盤監視に使い分ける。

アラートストーム防止の核心は3つ：**Composite Monitorによる複合条件化**、**Webhook+Downtimeによる依存関係ベースの自動抑制**、**統一タグによるスコープ管理**である。これらを組み合わせることで、根本原因1件に対して1つのアラートのみが発生する、ノイズのない監視体制を構築できる。