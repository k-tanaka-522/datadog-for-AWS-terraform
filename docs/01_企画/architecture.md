# アーキテクチャ設計パターン

## 本プロジェクトの構成

リソースタイプ別に分離した小〜中規模向け構成:

```
terraform/datadog/
├── integration.tf          # AWS Integration
├── monitoring/             # アラート系
│   └── modules/
│       ├── level0-infra/
│       ├── level2-health/
│       ├── level3-tenant/
│       └── composite/
└── dashboards/             # 可視化系
```

## 規模別の代替パターン

### パターンA: リソースタイプ別 (本プロジェクト)

```
datadog/
├── monitoring/
│   └── modules/
│       ├── level0-infra/
│       ├── level2-health/
│       ├── level3-tenant/
│       └── composite/
├── dashboards/
├── slo/
└── maintenance/
```

**適用規模**: 小〜中 (テナント数 1-20)

**メリット**:
- Datadog のリソース構造と一致
- 1人〜少人数チームで管理しやすい
- モニター/ダッシュボードの見通しが良い

**デメリット**:
- 大規模になると monitoring/ が肥大化
- チーム分担しにくい

---

### パターンB: レイヤー別

```
datadog/
├── infra/                  # L0: インフラ担当
│   ├── monitors.tf
│   ├── dashboards.tf
│   └── slo.tf
│
├── platform/               # L1-L2: プラットフォーム担当
│   ├── monitors.tf
│   └── dashboards.tf
│
└── tenants/                # L3: アプリ担当
    ├── modules/
    │   └── tenant/
    ├── acme.tf
    ├── globex.tf
    └── dashboards.tf
```

**適用規模**: 中〜大 (テナント数 10-100)

**メリット**:
- チーム別に責任分担可能
- インフラ変更がアプリ監視に影響しにくい
- 権限分離しやすい

**デメリット**:
- ファイル数が増える
- Composite Monitor の連携が複雑

---

### パターンC: ドメイン別 (マイクロサービス向け)

```
datadog/
├── rds/
│   ├── monitors.tf
│   ├── dashboards.tf
│   └── slo.tf
│
├── ecs/
│   ├── monitors.tf
│   ├── dashboards.tf
│   └── slo.tf
│
├── alb/
│   └── monitors.tf
│
├── tenant-acme/
│   ├── monitors.tf
│   ├── dashboards.tf
│   └── slo.tf
│
└── tenant-globex/
    └── ...
```

**適用規模**: 大規模 (テナント数 50+、マイクロサービス)

**メリット**:
- ドメインごとに完全独立
- 個別デプロイ可能
- マイクロサービスと相性良い

**デメリット**:
- 重複コードが増える
- Composite Monitor の管理が複雑
- 全体の見通しが悪い

---

### パターンD: Terragrunt 使用 (エンタープライズ)

```
datadog/
├── terragrunt.hcl          # 共通設定
│
├── _modules/               # 共通モジュール
│   ├── monitor/
│   ├── dashboard/
│   └── slo/
│
├── production/
│   ├── terragrunt.hcl
│   ├── infra/
│   │   └── terragrunt.hcl
│   └── tenants/
│       ├── acme/
│       │   └── terragrunt.hcl
│       └── globex/
│           └── terragrunt.hcl
│
└── staging/
    └── ...
```

**適用規模**: エンタープライズ (環境複数、テナント 100+)

**メリット**:
- DRY (Don't Repeat Yourself)
- 環境別の設定管理が容易
- 依存関係の自動解決

**デメリット**:
- Terragrunt の学習コスト
- デバッグが複雑
- チームメンバー全員が理解必要

---

## 選定ガイド

```
┌─────────────────────────────────────────────────────────────┐
│                     選定フローチャート                       │
└─────────────────────────────────────────────────────────────┘

テナント数は?
    │
    ├─ 1-20 ──────────────────→ パターンA (リソースタイプ別)
    │
    ├─ 20-100 ────┬─ チーム1つ → パターンA
    │             └─ チーム複数 → パターンB (レイヤー別)
    │
    └─ 100+ ──────┬─ モノリス → パターンB
                  ├─ マイクロサービス → パターンC (ドメイン別)
                  └─ 環境複数 → パターンD (Terragrunt)
```

## AWS 側の構成パターン

### パターンA: 機能別 (本プロジェクト)

```
aws/
├── network/
├── database/
├── compute/
├── loadbalancer/
└── ecr/
```

### パターンB: レイヤー別

```
aws/
├── base/               # VPC, IAM
├── data/               # RDS, ElastiCache
├── app/                # ECS, Lambda
└── edge/               # ALB, CloudFront
```

### パターンC: 環境分離

```
aws/
├── modules/
│   ├── network/
│   ├── database/
│   └── compute/
│
├── dev/
│   └── main.tf         # module 呼び出し
├── staging/
│   └── main.tf
└── production/
    └── main.tf
```

## 移行ガイド

### パターンA → B への移行

1. 新しいディレクトリ構造を作成
2. `terraform state mv` でリソースを移動
3. import/state mv を使って State を再編成

```bash
# 例: monitoring/ 配下を infra/ と tenants/ に分割
terraform state mv module.level0 module.infra.level0
terraform state mv module.level3 module.tenants.level3
```

### State 分割時の注意

- 分割前に `terraform state pull > backup.tfstate` でバックアップ
- Composite Monitor の参照関係を確認
- 段階的に移行（一度に全部やらない）
