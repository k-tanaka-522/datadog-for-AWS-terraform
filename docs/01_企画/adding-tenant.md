# テナント追加手順

## 概要

本プロジェクトでは、テナント追加は `tenants.tfvars` を編集して `terraform apply` するだけで完了する。

以下のリソースが自動で作成される:

- **AWS側**
  - ALB Listener Rule (パスルーティング)
  - Target Group
  - ECS Service
  - ECS Task Definition
  - CloudWatch Log Group

- **Datadog側**
  - L2: Synthetics ヘルスチェック
  - L3: エラーログ監視
  - L3: レイテンシ監視
  - L3: エラー率監視
  - Composite Monitor (親子関係)

## 手順

### 1. テナント定義を追加

```bash
vim terraform/shared/tenants.tfvars
```

```hcl
# terraform/shared/tenants.tfvars

tenants = {
  # 既存テナント
  "acme" = {
    display_name          = "Acme Corporation"
    path_pattern          = "/acme/*"
    health_path           = "/acme/health"
    priority              = 100
    desired_count         = 1
    cpu                   = 256
    memory                = 512
    error_log_threshold   = 10
    latency_p99_threshold = 500
    error_rate_threshold  = 5
    slack_channel         = "alerts-acme"
  }

  # ↓ 新規テナント追加
  "newcorp" = {
    display_name          = "New Corporation"
    path_pattern          = "/newcorp/*"
    health_path           = "/newcorp/health"
    priority              = 200              # 他と重複しない値
    desired_count         = 1
    cpu                   = 256
    memory                = 512
    error_log_threshold   = 10
    latency_p99_threshold = 500
    error_rate_threshold  = 5
    slack_channel         = "alerts-newcorp"
  }
}
```

### 2. RDS にテナント用スキーマ作成

```bash
# RDS に接続
psql -h <rds-endpoint> -U postgres -d demo

# スキーマ作成
CREATE SCHEMA newcorp;

# テーブル作成 (アプリと合わせる)
CREATE TABLE newcorp.items (
  id SERIAL PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

# ヘルスチェック用
CREATE TABLE newcorp.health_check (
  id INTEGER PRIMARY KEY DEFAULT 1,
  status VARCHAR(10) DEFAULT 'ok'
);
INSERT INTO newcorp.health_check VALUES (1, 'ok');
```

### 3. AWS リソースをデプロイ

```bash
cd terraform/aws

# 差分確認
terraform plan -var-file=../shared/tenants.tfvars

# 期待される出力:
# + aws_lb_target_group.tenant["newcorp"]
# + aws_lb_listener_rule.tenant["newcorp"]
# + aws_ecs_service.tenant["newcorp"]
# + aws_ecs_task_definition.tenant["newcorp"]
# + aws_cloudwatch_log_group.tenant["newcorp"]

# 適用
terraform apply -var-file=../shared/tenants.tfvars
```

### 4. 動作確認

```bash
# ALB エンドポイント取得
ALB_DNS=$(terraform output -raw alb_dns_name)

# ヘルスチェック
curl http://${ALB_DNS}/newcorp/health
# {"status": "ok", "tenant": "newcorp"}

# API テスト
curl http://${ALB_DNS}/newcorp/items
```

### 5. Datadog 監視をデプロイ

```bash
cd terraform/datadog

# 差分確認
terraform plan -var-file=../shared/tenants.tfvars

# 期待される出力:
# + module.level2.datadog_synthetics_test.health["newcorp"]
# + module.level3["newcorp"].datadog_monitor.error_logs
# + module.level3["newcorp"].datadog_monitor.error_rate
# + module.level3["newcorp"].datadog_monitor.latency_p99
# + module.composite["newcorp"].datadog_monitor.composite

# 適用
terraform apply -var-file=../shared/tenants.tfvars
```

### 6. Datadog で確認

- Monitors: `tenant:newcorp` でフィルタ
- Synthetics: `/newcorp/health` のテスト確認

## パラメータ説明

| パラメータ | 説明 | 例 |
|-----------|------|-----|
| `display_name` | 表示名 (ダッシュボード用) | "New Corporation" |
| `path_pattern` | ALB ルーティングパス | "/newcorp/*" |
| `health_path` | ヘルスチェックパス | "/newcorp/health" |
| `priority` | ALB ルール優先度 (1-50000、重複不可) | 200 |
| `desired_count` | ECS タスク数 | 1 |
| `cpu` | CPU (256 = 0.25 vCPU) | 256, 512, 1024 |
| `memory` | メモリ (MB) | 512, 1024, 2048 |
| `error_log_threshold` | エラーログ閾値 (5分間) | 10 |
| `latency_p99_threshold` | p99 レイテンシ閾値 (ms) | 500 |
| `error_rate_threshold` | エラー率閾値 (%) | 5 |
| `slack_channel` | 通知先 Slack チャンネル | "alerts-newcorp" |

## priority の管理

ALB Listener Rule の priority は重複できない。
新規追加時は既存の最大値 + 100 を推奨:

```bash
# 現在の priority 確認
grep -E "priority\s*=" terraform/shared/tenants.tfvars
```

推奨ルール:
- 100 刻みで割り当て (100, 200, 300...)
- 間に挿入が必要な場合は 10 刻み (110, 120...)

## トラブルシューティング

### ECS タスクが起動しない

```bash
# タスク停止理由確認
aws ecs describe-tasks \
  --cluster demo-dev \
  --tasks $(aws ecs list-tasks --cluster demo-dev --service api-newcorp --query 'taskArns[0]' --output text)
```

よくある原因:
- DB 接続エラー → スキーマ未作成
- イメージ pull 失敗 → ECR 権限
- ヘルスチェック失敗 → パス設定ミス

### Datadog にメトリクスが来ない

- AWS Integration 設定確認
- ECS タスクの Datadog Agent ログ確認
- タグ `tenant:newcorp` が付いているか確認

### Synthetics テストが失敗

- ALB が HTTPS 必須の場合、URL スキーム確認
- Security Group で Datadog IP 許可確認
