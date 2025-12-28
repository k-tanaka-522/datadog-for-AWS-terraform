# Datadog + ECS マルチテナント監視デモ

Terraform を使用した AWS ECS マルチテナント環境の構築と、Datadog による階層型監視体制の検証プロジェクト。

## 概要

### 目的

- Terraform による Datadog 監視の IaC 化
- マルチテナント環境でのテナント追加時の監視自動デプロイ
- Composite Monitor による親子関係アラート制御（アラートストーム防止）

### アーキテクチャ

```
                              Datadog
            ┌─────────────────────────────────────────────┐
            │   [L0] RDS/ECS基盤監視 (親)                 │
            │          ↓ OKなら                          │
            │   [L2] テナント別ヘルスチェック (親)        │
            │          ↓ OKなら                          │
            │   [L3] テナント別詳細監視 (子)              │
            │        - エラーログ                         │
            │        - レイテンシ                         │
            │        - エラー率                           │
            └─────────────────────────────────────────────┘
                              ▲
                    メトリクス/ログ
                              │
            ┌─────────────────────────────────────────────┐
            │                   AWS                        │
            │                                              │
            │   ALB ──┬─ /acme/*   → ECS-acme   ─┐       │
            │         └─ /globex/* → ECS-globex ─┼→ RDS  │
            │                                     │       │
            │         (テナント追加で自動拡張)           │
            └─────────────────────────────────────────────┘
```

## 前提条件

- AWS CLI 設定済み
- Terraform >= 1.5
- Docker / Docker Compose
- Datadog アカウント（フリープランでも可）

## クイックスタート

### 1. シークレット準備

```bash
# Datadog API Key / App Key を取得
# https://app.datadoghq.com/organization-settings/api-keys

# 環境変数設定
export DD_API_KEY="your-api-key"
export DD_APP_KEY="your-app-key"
export AWS_PROFILE="your-profile"
```

### 2. Terraform Backend 準備

```bash
# S3バケット作成 (初回のみ)
./scripts/setup-backend.sh
```

### 3. ローカル動作確認

```bash
cd app
docker-compose up -d
curl http://localhost:8080/acme/health
```

### 4. AWS デプロイ

```bash
cd terraform/aws
terraform init
terraform plan -var-file=../shared/tenants.tfvars
terraform apply -var-file=../shared/tenants.tfvars
```

### 5. Datadog 監視デプロイ

```bash
cd terraform/datadog
terraform init
terraform plan -var-file=../shared/tenants.tfvars
terraform apply -var-file=../shared/tenants.tfvars
```

## ディレクトリ構成

```
datadog-ecs-demo/
├── app/                        # FastAPI アプリケーション
│   ├── main.py
│   ├── database.py
│   ├── Dockerfile
│   ├── requirements.txt
│   └── docker-compose.yml      # ローカル開発用
│
├── terraform/
│   ├── shared/
│   │   └── tenants.tfvars      # ★ テナント定義 (単一ソース)
│   │
│   ├── aws/                    # AWS インフラ
│   │   ├── network/            # VPC, Subnet, SG
│   │   ├── database/           # RDS PostgreSQL
│   │   ├── compute/            # ECS Cluster, Service, Task
│   │   ├── loadbalancer/       # ALB, Target Group
│   │   ├── ecr/                # Container Registry
│   │   └── datadog/            # DD Agent用 IAM, Secrets
│   │
│   └── datadog/                # Datadog 監視
│       ├── integration.tf      # AWS Integration
│       ├── monitoring/         # アラート設定
│       │   └── modules/
│       │       ├── level0-infra/
│       │       ├── level2-health/
│       │       ├── level3-tenant/
│       │       └── composite/
│       └── dashboards/         # ダッシュボード
│
├── scripts/
│   ├── setup-backend.sh        # Terraform backend 初期化
│   ├── deploy-aws.sh
│   ├── deploy-datadog.sh
│   └── destroy-all.sh
│
└── docs/
    ├── terraform-state.md      # State管理について
    ├── adding-tenant.md        # テナント追加手順
    ├── monitoring-design.md    # 監視設計
    └── synthetics.md           # Synthetics説明
```

## テナント追加手順

詳細: [docs/adding-tenant.md](docs/adding-tenant.md)

```bash
# 1. tenants.tfvars 編集
vim terraform/shared/tenants.tfvars

# 2. AWS リソース追加
cd terraform/aws && terraform apply -var-file=../shared/tenants.tfvars

# 3. Datadog 監視追加
cd terraform/datadog && terraform apply -var-file=../shared/tenants.tfvars
```

## Composite Monitor (親子関係)

インフラ障害時にアプリケーションアラートを抑制する仕組み。

```
例: RDS障害発生時

  [L0] RDS CPU 100% → ALERT 🔔 (これだけ通知)
       ↓ 抑制
  [L2] Health NG   → (発火しない)
       ↓ 抑制
  [L3] Error Logs  → (発火しない) ← DBエラーログは当然出るが黙る
```

詳細: [docs/monitoring-design.md](docs/monitoring-design.md)

## コスト概算

| リソース | 月額 |
|---------|------|
| RDS db.t4g.micro | $12 |
| ECS Fargate (2 tasks) | $20 |
| ALB | $20 |
| ECR, Secrets Manager | $2 |
| **合計** | **約 $55/月** |

※ NAT Gateway なし構成（Fargate を Public Subnet に配置）

## 注意事項

- 本番環境では NAT Gateway + Private Subnet 構成を推奨
- RDS Multi-AZ は検証用のため無効化
- Datadog フリープランでは一部機能に制限あり

## 設計パターン比較

本プロジェクトは小〜中規模向けの構成。規模に応じて以下の構成も検討可能:

| パターン | 適用規模 | 特徴 |
|----------|----------|------|
| 本構成 (リソースタイプ別) | 小〜中 | monitoring/, dashboards/ で分離 |
| レイヤー別 | 中〜大 | infra/, tenants/ でチーム分担 |
| ドメイン別 | 大規模 | rds/, ecs/, tenant-xxx/ で完全分離 |

詳細: [docs/architecture.md](docs/architecture.md)

## ライセンス

MIT
