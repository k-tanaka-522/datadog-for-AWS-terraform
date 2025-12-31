# Datadog監視基盤 Terraform

Terraformを使用してDatadog MonitorをIaC化したプロジェクトです。

## 概要

L0（インフラ）、L2（サービス）、L3（テナント）の3層監視とComposite Monitorによるアラート抑制を実現します。

## 目次

- [プロジェクト構成](#プロジェクト構成)
- [監視階層の全体像](#監視階層の全体像)
- [なぜこの設計なのか](#なぜこの設計なのか)
- [事前準備](#事前準備)
- [デプロイ手順](#デプロイ手順)
- [作成されるMonitor数](#作成されるmonitor数)
- [よくある質問（FAQ）](#よくある質問faq)
- [用語集](#用語集)
- [トラブルシューティング](#トラブルシューティング)

---

## プロジェクト構成

```
terraform/
├── aws/                        # AWS基盤（将来実装予定）
│   └── .gitkeep
└── datadog/                    # Datadog監視設定
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

**ディレクトリ再構成に伴う注意**:
- 2025-12-29: ディレクトリ構成を変更しました（設計書との対応を明確化）
- 既存環境で作業している場合は、`terraform init -reconfigure` を実行してください
- backend.tf の State ファイルパスが `datadog/terraform.tfstate` に変更されています

---

## 監視階層の全体像

### 階層構造と Composite Monitor のアラート抑制

```
┌──────────────────────────────────────────────────────────────────┐
│ [L0] インフラ基盤監視（親）                                      │
│ RDS/ECS/VPC/Agent（7個のMonitor）                               │
│                                                                  │
│ NG: RDS接続失敗、ECS Task異常終了 → 【アラート通知】           │
│ OK: インフラ正常 → 次の層をチェック                            │
└──────────┬───────────────────────────────────────────────────────┘
           ↓ インフラOKの場合のみチェック
┌──────────────────────────────────────────────────────────────────┐
│ [L2] サービス監視（子）                                          │
│ ALB/ECS Task/ECR/E2E ヘルスチェック（4個のMonitor）             │
│                                                                  │
│ NG: ALB 5xx急増、ヘルスチェック失敗 → 【アラート通知】         │
│     （ただしL0がNGなら通知抑制）                                │
│ OK: サービス正常 → 次の層をチェック                            │
└──────────┬───────────────────────────────────────────────────────┘
           ↓ インフラ・サービスOKの場合のみチェック
┌──────────────────────────────────────────────────────────────────┐
│ [L3] テナント詳細監視（子）                                      │
│ ヘルスチェック/エラーログ/レイテンシ（3個×テナント数）         │
│                                                                  │
│ NG: tenant-a でエラーログ急増 → 【アラート通知】               │
│     （ただしL0/L2がNGなら通知抑制）                            │
│ OK: 全て正常                                                    │
└──────────────────────────────────────────────────────────────────┘
```

### Composite Monitor による通知制御の仕組み

**シナリオ1: RDS障害時（インフラ障害）**

```
RDS接続失敗 → L0 NG
  ↓
L0がNGなので、L2/L3の通知を抑制
  ↓
【結果】L0のアラートのみ通知（根本原因はRDS）
```

**シナリオ2: テナント個別障害時**

```
RDS正常 → L0 OK
  ↓
ALB正常、ECS正常 → L2 OK
  ↓
tenant-a でエラーログ急増 → L3 (tenant-a) NG
  ↓
【結果】L3 (tenant-a) のアラートのみ通知（個別障害）
```

**効果**: アラート疲れを防ぎ、根本原因を素早く特定できます。

---

## なぜこの設計なのか

### なぜ S3 + DynamoDB で State 管理するのか

**理由1: リモートバックエンドによるチーム作業**
- Terraformの実行結果（State）をローカルPCではなくS3に保存
- チームメンバー全員が同じStateを参照できる
- ローカルPCが壊れてもStateは安全

**理由2: State ロックによる同時実行防止**
- DynamoDBで排他制御（ロック）を実現
- 複数メンバーが同時に `terraform apply` しても競合しない
- 「誰かが実行中」なら他のメンバーはロック待ちになる

**理由3: Stateのバージョニング**
- S3のバージョニング機能で、誤削除やロールバックに対応
- `terraform destroy` を誤実行しても復旧可能

**参考**: [Terraform Backend S3](https://developer.hashicorp.com/terraform/language/settings/backends/s3)

### なぜ API Key を環境変数で渡すのか

**理由1: セキュリティ（機密情報漏洩防止）**
- `terraform.tfvars` にAPI Keyを書くと、誤ってGitにコミットするリスクがある
- 環境変数なら、Gitリポジトリに一切残らない

**理由2: CI/CD パイプラインとの親和性**
- GitLab CI、GitHub Actionsなどでは環境変数でSecretsを注入するのが標準
- ローカル開発とCI/CDで同じ運用方法を使える

**理由3: Git履歴への漏洩防止**
- 一度Gitにコミットすると、削除しても履歴に残る
- 環境変数なら、最初から履歴に載らない

**ベストプラクティス**:
```powershell
# 環境変数で注入（推奨）
$env:TF_VAR_datadog_api_key = $env:DD_API_KEY

# ❌ tfvarsに直接書く（非推奨）
# datadog_api_key = "abcd1234..."  # Gitにコミットすると漏洩リスク
```

### なぜモジュール化しているのか

**理由1: 再利用性（DRY原則）**
- L3モジュールを `for_each` で展開すれば、テナントごとに同じMonitorを自動生成
- コードの重複を避け、保守性が向上

**理由2: 責任の分離**
- `modules/level0-infra/` はインフラ監視の責任のみを持つ
- `main.tf` は各モジュールの組み立てのみを担当

**理由3: テストしやすさ**
- モジュール単位でテスト可能（Terratest等）
- 変更影響範囲が明確になる

**例**: L3モジュールを1回定義すれば、100テナントでも1000テナントでも自動展開可能

```hcl
# L3モジュールを for_each で展開
module "level3" {
  source   = "./modules/level3-tenant"
  for_each = var.tenants  # テナント数だけ繰り返し
  ...
}
```

### なぜ Composite Monitor を使うのか

**理由1: アラート疲れ防止**
- インフラ障害時に「RDS NG、ALB NG、tenant-a NG、tenant-b NG…」と通知が殺到するのを防ぐ
- Composite Monitorで「L0がNGならL2/L3は通知しない」という制御が可能

**理由2: 根本原因の特定**
- 通知メールを見れば「L0がNGだからインフラ障害」とすぐわかる
- テナント個別の障害か、全体障害かを瞬時に判断できる

**理由3: Datadog の推奨パターン**
- [Datadog公式ドキュメント](https://docs.datadoghq.com/monitors/types/composite/)でも階層型監視に推奨されている

**参考**: 本プロジェクトでは、L0/L2/L3の3層に分けてComposite Monitorを構成しています。

### なぜ for_each でテナントを展開するのか

**理由1: DRY原則（Don't Repeat Yourself）**
- テナントごとにMonitorを手動コピペすると、修正時に全て書き換える必要がある
- `for_each` なら、1箇所修正すれば全テナントに反映される

**理由2: スケーラビリティ**
- テナント追加時は `terraform.tfvars` に1行追加 → `terraform apply` で自動作成
- 100テナントでも1000テナントでも同じコードで対応可能

**理由3: 一貫性**
- 全テナントで同じ監視ルールが適用される
- 手動作成だと、設定ミスや漏れが発生しやすい

**例**:
```hcl
# terraform.tfvars にテナント追加
tenants = {
  tenant-a = { errors_threshold = 10, latency_threshold = 1000 }
  tenant-b = { errors_threshold = 10, latency_threshold = 1000 }
  tenant-d = { errors_threshold = 10, latency_threshold = 1000 }  # ← 追加
}
```

→ `terraform apply` で tenant-d 用のMonitor 3個が自動作成される

---

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

---

## デプロイ手順

### 初回デプロイ

```powershell
# ディレクトリ移動
cd infra/terraform/datadog

# 1. Terraform 初期化
terraform init

# 2. plan（dry-run）
terraform plan -out=tfplan

# 3. 確認後、apply
terraform apply tfplan
```

### 既存環境でディレクトリ再構成後の再初期化

```powershell
# ディレクトリ移動
cd infra/terraform/datadog

# 既存の .terraform を削除
Remove-Item -Recurse -Force .terraform

# backend 設定を再初期化（-reconfigure で既存 State を引き継ぐ）
terraform init -reconfigure

# State ファイルの移行が必要な場合（旧パスから新パスへ）
# AWS CLIで手動コピー:
# aws s3 cp s3://datadog-terraform-state/datadog-monitors/terraform.tfstate s3://datadog-terraform-state/datadog/terraform.tfstate

# plan で差分なしを確認
terraform plan
# Output: No changes. Your infrastructure matches the configuration.
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

---

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

---

## よくある質問（FAQ）

### Q1. `terraform plan` で差分が出るけど大丈夫ですか？

**A**: 以下の差分は正常です。

**パターン1: Datadog側で手動変更した場合**
```
# datadog_monitor.example will be updated in-place
  ~ message = "old message" -> "new message"
```
→ `terraform apply` すれば、Terraformの定義に戻ります。

**パターン2: 既知の差分（query の正規化等）**
```
# datadog_monitor.example will be updated in-place
  ~ query = "avg(last_5m):avg:system.cpu.user{*} by {host} > 80"
          -> "avg(last_5m):avg:system.cpu.user{*} by {host} > 80.0"
```
→ Datadogが内部で正規化しているだけなので、影響なし。

**パターン3: 異常な差分（意図しない削除・追加）**
```
# module.level3["tenant-a"].datadog_monitor.health will be destroyed
```
→ **STOP!** tfvarsの定義が消えていないか確認。誤って削除すると全Monitorが消える。

**ベストプラクティス**: 初回デプロイ後、毎回 `terraform plan` して差分なしを確認してから本番作業へ。

---

### Q2. モニターが No Data になる原因は？

**A**: 以下を確認してください。

**原因1: Datadog Agent が起動していない**
```powershell
# ECS Task のログを確認
aws ecs describe-tasks --cluster datadog-poc-cluster --tasks <task-id>
```

**原因2: メトリクスのタグが間違っている**
```
# 例: tenant:tenant-a のはずが tenant:tenant_a になっている
# Datadog UI で Metrics Explorer を開いて、実際のタグを確認
```

**原因3: APM トレースが送信されていない**
```python
# demo-api のコードで ddtrace が有効か確認
# app/src/app.py の span.set_tag("tenant", tenant_id) が実行されているか
```

**原因4: 閾値が厳しすぎる**
```hcl
# latency_threshold = 100ms → 200ms に緩和
tenants = {
  tenant-a = { errors_threshold = 10, latency_threshold = 200 }
}
```

**デバッグ方法**:
1. Datadog UI → Metrics Explorer で対象メトリクスを検索
2. `tenant:tenant-a` でフィルタして、データが来ているか確認
3. データが来ていない場合、Agentログ・APMトレースを確認

---

### Q3. テナントを削除したいときはどうしますか？

**A**: terraform.tfvars から該当テナントを削除 → `terraform apply` で自動削除されます。

**手順**:
```hcl
# terraform.tfvars
tenants = {
  tenant-a = { errors_threshold = 10, latency_threshold = 1000 }
  # tenant-b = { errors_threshold = 10, latency_threshold = 1000 }  # ← 削除（コメントアウト）
  tenant-c = { errors_threshold = 10, latency_threshold = 1000 }
}
```

```powershell
# 1. plan で削除対象を確認
terraform plan -out=tfplan
# Plan: 0 to add, 0 to change, 3 to destroy.
# （tenant-b のL3 Monitor 3個が削除される）

# 2. 問題なければ apply
terraform apply tfplan
```

**注意**: 削除されるMonitorは復元できません。バックアップが必要な場合は、事前に `terraform show` でStateを保存してください。

---

### Q4. CI/CD パイプラインで自動デプロイしたいのですが？

**A**: GitLab CI / GitHub Actions でのサンプル実装例を示します。

**GitHub Actions の例**:
```yaml
# .github/workflows/terraform-datadog.yml
name: Terraform Datadog Deploy

on:
  push:
    branches: [main]
    paths:
      - 'infra/terraform/datadog/**'

jobs:
  terraform:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v2

      - name: Terraform Init
        run: terraform init
        working-directory: infra/terraform/datadog

      - name: Terraform Plan
        run: terraform plan -out=tfplan
        working-directory: infra/terraform/datadog
        env:
          TF_VAR_datadog_api_key: ${{ secrets.DD_API_KEY }}
          TF_VAR_datadog_app_key: ${{ secrets.DD_APP_KEY }}

      - name: Terraform Apply
        if: github.ref == 'refs/heads/main'
        run: terraform apply -auto-approve tfplan
        working-directory: infra/terraform/datadog
```

**重要**: GitHub Secrets に `DD_API_KEY`, `DD_APP_KEY` を登録してください。

---

### Q5. 現在の環境情報を確認したい

**A**: 以下のリソースが現在デプロイされています（2025-12-30時点）。

| リソース | 識別子 |
|---------|--------|
| ALB FQDN | `datadog-poc-alb-2037337052.ap-northeast-1.elb.amazonaws.com` |
| ECS Cluster | `datadog-poc-cluster` |
| RDS Instance | `datadog-poc-db` |
| ECR Repository | `demo-api` |
| ECS Service | `demo-api` |
| テナント | `tenant-a`, `tenant-b`, `tenant-c` |

**ヘルスチェックURL**:
```
http://datadog-poc-alb-2037337052.ap-northeast-1.elb.amazonaws.com/tenant-a/health
http://datadog-poc-alb-2037337052.ap-northeast-1.elb.amazonaws.com/tenant-b/health
http://datadog-poc-alb-2037337052.ap-northeast-1.elb.amazonaws.com/tenant-c/health
```

**確認方法**:
```powershell
# 現在の State を確認
terraform show

# 特定のリソースを確認
terraform state show module.level3["tenant-a"].datadog_monitor.health
```

---

## 用語集

### Terraform 用語

| 用語 | 説明 |
|-----|------|
| **State** | Terraformが管理するリソースの現在の状態。S3に保存され、チームで共有される。 |
| **Backend** | Stateの保存先（本プロジェクトではS3 + DynamoDB）。リモートバックエンドを使うことでチーム作業が可能になる。 |
| **Provider** | TerraformがAPIを呼び出す先（本プロジェクトでは Datadog, AWS）。 |
| **Module** | 再利用可能なTerraformコードのまとまり。`modules/level0-infra/` など。 |
| **for_each** | map型の変数をループして、複数リソースを自動生成する構文。テナント展開に使用。 |
| **tfvars** | 変数の値を定義するファイル。`terraform.tfvars` は機密情報を含むため.gitignore対象。 |
| **Plan** | `terraform plan` の実行結果。dry-runとして差分を確認できる。 |
| **Apply** | `terraform apply` でPlanを実行し、実際にリソースを作成・更新・削除する。 |

### Datadog 用語

| 用語 | 説明 |
|-----|------|
| **Monitor** | メトリクス・ログを監視し、閾値を超えたらアラートを発火するDatadogのリソース。 |
| **Composite Monitor** | 複数のMonitorを組み合わせて、親子関係・AND/OR条件を設定できるMonitor。アラート抑制に使用。 |
| **APM (Application Performance Monitoring)** | アプリケーションのトレースを収集し、レイテンシ・エラー率を可視化する機能。 |
| **Agent** | EC2/ECS/Fargate上で動作し、メトリクス・ログ・トレースをDatadogに送信するプロセス。 |
| **Tag** | メトリクス・トレースに付与するラベル。`tenant:tenant-a` など。 |
| **Metric** | CPU使用率、メモリ使用率など、数値化された指標。 |
| **Trace** | リクエストの処理経路を記録したデータ。APMで収集される。 |

### AWS 用語

| 用語 | 説明 |
|-----|------|
| **ECS (Elastic Container Service)** | コンテナオーケストレーションサービス。Fargate または EC2 上でコンテナを実行。 |
| **ALB (Application Load Balancer)** | L7ロードバランサー。HTTPSリクエストをECS Taskにルーティング。 |
| **RDS (Relational Database Service)** | マネージドRDBMSサービス。本プロジェクトではPostgreSQLを使用。 |
| **ECR (Elastic Container Registry)** | Dockerイメージのプライベートレジストリ。 |
| **VPC (Virtual Private Cloud)** | AWSの仮想ネットワーク。 |
| **S3 (Simple Storage Service)** | オブジェクトストレージ。Terraform Stateの保存先。 |
| **DynamoDB** | NoSQLデータベース。Terraform StateのLock管理に使用。 |

---

## トラブルシューティング

### よくあるエラー

| エラー | 原因 | 対処 |
|------|------|------|
| `Error: Invalid provider credentials` | Datadog API Key/APP Key が未設定 | 環境変数 `TF_VAR_datadog_api_key` を設定 |
| `Error: Backend initialization required` | backend.tf の S3バケットが存在しない | S3バケットを作成 |
| `Error: Monitor already exists` | 手動作成したMonitorと名前が重複 | 既存Monitorを削除、または terraform import |
| `Error: for_each argument is invalid` | `tenants` 変数がmap型でない | terraform.tfvars を確認 |
| `Error: Error acquiring the state lock` | 他のメンバーが terraform 実行中 | 待つか、緊急時は DynamoDB でLockを手動削除 |
| `Error: No data for monitor` | メトリクスが送信されていない | Datadog Agent のログを確認 |

### デバッグ方法

```powershell
# Terraform ログレベルを DEBUG に設定
$env:TF_LOG = "DEBUG"
terraform plan

# ログをファイルに保存
terraform plan 2>&1 | Out-File -FilePath terraform-debug.log

# State の内容を確認
terraform show

# 特定のリソースの詳細を確認
terraform state show module.level3["tenant-a"].datadog_monitor.health

# Datadog Provider の API コールをトレース
$env:TF_LOG_PROVIDER = "TRACE"
terraform plan
```

### State ロックの強制解除（緊急時のみ）

**注意**: 他のメンバーが実行中の場合、Stateが破壊される可能性があります。必ず確認してから実行してください。

```powershell
# DynamoDB でロックを確認
aws dynamodb get-item `
  --table-name terraform-state-lock `
  --key '{"LockID":{"S":"datadog-terraform-state/datadog/terraform.tfstate"}}'

# ロックを強制解除
terraform force-unlock <LOCK_ID>
```

---

## 関連ドキュメント

| ドキュメント | パス |
|------------|------|
| 基本設計書（全体） | `../../docs/04_インフラ設計/01_基本設計/` |
| 詳細設計書（全体） | `../../docs/04_インフラ設計/02_詳細設計/` |
| 詳細設計INDEX | `../../docs/04_インフラ設計/02_詳細設計/INDEX.md` |
| Terraform技術標準 | `../../.claude/docs/40_standards/42_infra/iac/terraform.md` |
| Datadog公式ドキュメント | https://docs.datadoghq.com/ |
| Terraform Datadog Provider | https://registry.terraform.io/providers/DataDog/datadog/latest/docs |

---

## セキュリティ

**機密情報の管理**:

| 機密情報 | 管理方法 | Gitコミット |
|---------|---------|-----------|
| Datadog API Key | 環境変数 `TF_VAR_datadog_api_key` | ❌ 禁止 |
| Datadog APP Key | 環境変数 `TF_VAR_datadog_app_key` | ❌ 禁止 |
| terraform.tfvars | ローカルファイル | ❌ 禁止（.gitignore） |
| terraform.tfvars.example | サンプル | ✅ コミット可（機密情報なし） |

**ベストプラクティス**:
- API Key は GitHub Secrets / GitLab CI Variables で管理
- ローカル開発では `.env` ファイル + `source .env` で環境変数を設定
- Terraform State（S3）へのアクセス権限は最小限に絞る

---

## ライセンス

（プロジェクトのライセンスを記載）

---

**作成日**: 2025-12-28
**更新日**: 2025-12-30
**作成者**: SRE
**バージョン**: 2.0
