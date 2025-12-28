# Datadog監視基盤 Terraform

Terraformを使用してDatadog MonitorをIaC化したプロジェクトです。

## 概要

L0（インフラ）、L2（サービス）、L3（テナント）の3層監視とComposite Monitorによるアラート抑制を実現します。

## プロジェクト構成

```
terraform/
├── main.tf                     # モジュール呼び出し
├── variables.tf                # 変数定義
├── outputs.tf                  # 出力定義
├── providers.tf                # Provider設定（Datadog、AWS）
├── backend.tf                  # State管理（S3 + DynamoDB）
├── terraform.tfvars.example    # サンプル（Gitにコミット）
├── .gitignore
└── modules/                    # 再利用可能なモジュール
    ├── level0-infra/           # L0 インフラ監視（7個のMonitor）
    ├── level2-service/         # L2 サービス監視（4個のMonitor）
    ├── level3-tenant/          # L3 テナント監視（3個のMonitor、for_each対応）
    └── composite/              # Composite Monitor（L0/L2/L3）
```

## 事前準備

### 1. S3バケットとDynamoDBテーブルの作成

Terraform Stateを管理するためのリソースを作成します。

```powershell
# S3バケット作成
aws s3 mb s3://datadog-terraform-state --region ap-northeast-1

# バージョニング有効化
aws s3api put-bucket-versioning `
  --bucket datadog-terraform-state `
  --versioning-configuration Status=Enabled

# DynamoDBテーブル作成
aws dynamodb create-table `
  --table-name terraform-state-lock `
  --attribute-definitions AttributeName=LockID,AttributeType=S `
  --key-schema AttributeName=LockID,KeyType=HASH `
  --billing-mode PAY_PER_REQUEST `
  --region ap-northeast-1
```

### 2. terraform.tfvars の作成

```powershell
# terraform.tfvars.example をコピー
cp terraform.tfvars.example terraform.tfvars

# terraform.tfvars を編集（AWS リソースID、テナント定義等）
```

**重要**: `terraform.tfvars` は機密情報を含むため、Gitにコミットしないでください（.gitignoreに含まれています）。

### 3. Datadog API Key/APP Key の設定

```powershell
# 環境変数で注入（terraform.tfvarsには一切記載しない）
$env:TF_VAR_datadog_api_key = $env:DD_API_KEY
$env:TF_VAR_datadog_app_key = $env:DD_APP_KEY
```

## デプロイ手順

### 初回デプロイ

```powershell
# 1. Terraform 初期化
terraform init

# 2. plan（dry-run）
terraform plan -out=tfplan

# 3. 確認後、apply
terraform apply tfplan
```

### テナント追加デプロイ

terraform.tfvars にテナントを追加します。

```hcl
# terraform.tfvars
tenants = {
  tenant-a = { errors_threshold = 10, latency_threshold = 1000 }
  tenant-b = { errors_threshold = 10, latency_threshold = 1000 }
  tenant-c = { errors_threshold = 10, latency_threshold = 1000 }
  tenant-d = { errors_threshold = 10, latency_threshold = 1000 }  # ← 追加
}
```

```powershell
# 1. plan（dry-run）
terraform plan -out=tfplan

# 2. 差分確認（L3 Monitor 3個追加を確認）
# Plan: 3 to add, 0 to change, 0 to destroy.

# 3. apply
terraform apply tfplan
```

### 削除（PoC終了時）

```powershell
# ⚠️ 全ての Monitor を削除
terraform destroy
```

## 作成されるMonitor数

| Layer | Monitor種類 | 個数 | 備考 |
|-------|-----------|------|------|
| L0 | インフラ監視 | 7個 | RDS、ECS、VPC、Agent |
| L2 | サービス監視 | 4個 | ALB、ECS Task、ECR、E2Eヘルスチェック |
| L3 | テナント監視 | 3個×テナント数 | ヘルスチェック、エラーログ、レイテンシ |
| Composite | アラート抑制 | 3個+テナント数 | L0、L2、L3（テナントごと） |

**例**: テナント3個の場合、合計 **22個のMonitor** が作成されます。
- L0: 7個
- L2: 4個
- L3: 3個 × 3テナント = 9個
- Composite: 3個（L0、L2、L3×3テナント） = 合計5個

## トラブルシューティング

### よくあるエラー

| エラー | 原因 | 対処 |
|------|------|------|
| `Error: Invalid provider credentials` | Datadog API Key/APP Key が未設定 | 環境変数 `TF_VAR_datadog_api_key` を設定 |
| `Error: Backend initialization required` | backend.tf の S3バケットが存在しない | S3バケットを作成 |
| `Error: Monitor already exists` | 手動作成したMonitorと名前が重複 | 既存Monitorを削除、または terraform import |
| `Error: for_each argument is invalid` | `tenants` 変数がmap型でない | terraform.tfvars を確認 |

### デバッグ方法

```powershell
# Terraform ログレベルを DEBUG に設定
$env:TF_LOG = "DEBUG"
terraform plan

# ログをファイルに保存
terraform plan 2>&1 | Out-File -FilePath terraform-debug.log
```

## 関連ドキュメント

| ドキュメント | パス |
|------------|------|
| 基本設計書（全体） | `../../docs/04_インフラ設計/01_基本設計/` |
| 詳細設計書（全体） | `../../docs/04_インフラ設計/02_詳細設計/` |
| 詳細設計INDEX | `../../docs/04_インフラ設計/02_詳細設計/INDEX.md` |
| Terraform技術標準 | `../../.claude/docs/40_standards/42_infra/iac/terraform.md` |

## セキュリティ

**機密情報の管理**:

| 機密情報 | 管理方法 | Gitコミット |
|---------|---------|-----------|
| Datadog API Key | 環境変数 `TF_VAR_datadog_api_key` | ❌ 禁止 |
| Datadog APP Key | 環境変数 `TF_VAR_datadog_app_key` | ❌ 禁止 |
| terraform.tfvars | ローカルファイル | ❌ 禁止（.gitignore） |
| terraform.tfvars.example | サンプル | ✅ コミット可（機密情報なし） |

## ライセンス

（プロジェクトのライセンスを記載）

---

**作成日**: 2025-12-28
**作成者**: SRE
**バージョン**: 1.0
