# IaC構成方針（Terraform）

## 1. 概要

本PoCでは、Datadog監視設定をTerraformでIaC化します。以下の方針に従って実装します:

1. **モジュール化**: L0/L2/L3/Composite を独立したモジュールに分割
2. **テナント管理**: `for_each` でテナントを動的に展開
3. **環境差分管理**: 変数ファイル（tfvars）で環境差分を管理
4. **State管理**: S3 + DynamoDB でチーム共有

## 2. ディレクトリ構成

### 2.1 推奨構成（技術標準準拠）

```
terraform/
├── main.tf                     # ルートモジュール（モジュール呼び出し）
├── variables.tf                # 変数定義
├── outputs.tf                  # 出力定義
├── providers.tf                # Provider設定（Datadog、AWS）
├── backend.tf                  # State管理（S3 + DynamoDB）
├── terraform.tfvars            # 変数値（Gitにコミットしない）⭐
├── terraform.tfvars.example    # サンプル（Gitにコミット）
├── versions.tf                 # Terraform/Provider バージョン指定
│
├── modules/                    # 再利用可能なモジュール⭐
│   ├── level0-infra/           # L0 インフラ監視モジュール
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── monitors.tf         # L0 Monitor 定義
│   │
│   ├── level2-service/         # L2 サービス監視モジュール
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── monitors.tf         # L2 Monitor 定義
│   │
│   ├── level3-tenant/          # L3 テナント監視モジュール
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── monitors.tf         # L3 Monitor 定義（for_each対応）
│   │
│   └── composite/              # Composite Monitor モジュール
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── composites.tf       # Composite Monitor 定義
│
└── .terraform/                 # Terraform キャッシュ（Gitにコミットしない）
```

### 2.2 重要原則

**✅ テンプレートは環境共通（`modules/`）**
- モジュールは再利用可能な設計
- 環境（dev/stg/prd）に依存しない

**✅ 環境差分は変数で管理（`terraform.tfvars`）**
- テナント定義、閾値等を変数化
- 環境ごとに terraform.tfvars を切り替え（PoCでは1環境のみ）

**❌ 環境別にモジュールを複製しない**
- 同じコードを複数環境で使い回す

## 3. モジュール設計

### 3.1 level0-infra モジュール

#### 責務
- L0 インフラ監視 Monitor の作成（RDS、ECS Cluster、VPC、Datadog Agent）

#### ディレクトリ構成

```
modules/level0-infra/
├── main.tf           # モジュールのエントリーポイント
├── variables.tf      # 入力変数定義
├── outputs.tf        # 出力定義（Monitor ID等）
└── monitors.tf       # L0 Monitor の定義
```

#### variables.tf（例）

```hcl
variable "rds_instance_id" {
  description = "RDS インスタンス識別子"
  type        = string
}

variable "ecs_cluster_name" {
  description = "ECS Cluster 名"
  type        = string
}

variable "rds_cpu_threshold" {
  description = "RDS CPU使用率の閾値（%）"
  type        = number
  default     = 95
}

variable "tags" {
  description = "Monitor に付与するタグ"
  type        = map(string)
  default     = {}
}
```

#### monitors.tf（例）

```hcl
# L0-RDS-CPU Monitor
resource "datadog_monitor" "rds_cpu" {
  name    = "[L0] RDS CPU使用率"
  type    = "metric alert"
  query   = "avg(last_5m):avg:aws.rds.cpuutilization{dbinstanceidentifier:${var.rds_instance_id}} > ${var.rds_cpu_threshold}"
  message = <<-EOT
    [L0] RDS CPU使用率が${var.rds_cpu_threshold}%を超えました。
    - DB: ${var.rds_instance_id}
    - 影響: 全テナント
  EOT

  thresholds = {
    critical = var.rds_cpu_threshold
    warning  = 80
  }

  tags = merge(
    {
      layer    = "l0"
      resource = "rds"
      severity = "critical"
    },
    var.tags
  )
}

# 他の L0 Monitor も同様に定義
# L0-RDS-Conn, L0-RDS-Mem, L0-RDS-Storage, L0-ECS-Tasks, L0-VPC-Flow, L0-Agent
```

#### outputs.tf（例）

```hcl
output "monitor_ids" {
  description = "L0 Monitor のIDリスト"
  value = {
    rds_cpu     = datadog_monitor.rds_cpu.id
    rds_conn    = datadog_monitor.rds_conn.id
    rds_mem     = datadog_monitor.rds_mem.id
    rds_storage = datadog_monitor.rds_storage.id
    ecs_tasks   = datadog_monitor.ecs_tasks.id
    vpc_flow    = datadog_monitor.vpc_flow.id
    agent       = datadog_monitor.agent.id
  }
}
```

### 3.2 level2-service モジュール

#### 責務
- L2 サービス監視 Monitor の作成（ALB、ECS Task、ECR）

#### ディレクトリ構成

```
modules/level2-service/
├── main.tf
├── variables.tf
├── outputs.tf
└── monitors.tf       # L2 Monitor の定義
```

#### monitors.tf（例）

```hcl
# L2-ALB-Health Monitor
resource "datadog_monitor" "alb_health" {
  name    = "[L2] ALB Target Group Health"
  type    = "metric alert"
  query   = "avg(last_5m):avg:aws.applicationelb.healthy_host_count{targetgroup:${var.alb_target_group}} <= 0"
  message = <<-EOT
    [L2] ALB Target Groupのヘルシーホストが0になりました。
    - Target Group: ${var.alb_target_group}
    - 影響: 全テナント（サービス停止）
  EOT

  thresholds = {
    critical = 0
    warning  = 1
  }

  tags = merge(
    {
      layer    = "l2"
      resource = "alb"
      severity = "critical"
    },
    var.tags
  )
}

# 他の L2 Monitor も同様に定義
# L2-ECS-Task, L2-ECR-Vuln
```

### 3.3 level3-tenant モジュール（for_each 対応）

#### 責務
- L3 テナント監視 Monitor の作成（テナントごとに動的展開）

#### ディレクトリ構成

```
modules/level3-tenant/
├── main.tf
├── variables.tf
├── outputs.tf
└── monitors.tf       # L3 Monitor の定義（テナント変数を使用）
```

#### variables.tf（例）

```hcl
variable "tenant_id" {
  description = "テナント識別子（例: tenant-a）"
  type        = string
}

variable "health_check_url" {
  description = "ヘルスチェックURL（例: https://myapp.example.com/tenant-a/health）"
  type        = string
}

variable "errors_threshold" {
  description = "エラーログ数の閾値（5分間）"
  type        = number
  default     = 10
}

variable "latency_threshold" {
  description = "レイテンシ閾値（ms、p99）"
  type        = number
  default     = 1000
}

variable "tags" {
  description = "Monitor に付与するタグ"
  type        = map(string)
  default     = {}
}
```

#### monitors.tf（例）

```hcl
# L3-Health Monitor
resource "datadog_monitor" "health_check" {
  name    = "[L3] ${var.tenant_id} ヘルスチェック"
  type    = "service check"
  query   = "\"http.check\".over(\"url:${var.health_check_url}\").by(\"*\").last(2).count_by_status()"
  message = <<-EOT
    [L3] ${var.tenant_id} のヘルスチェックが失敗しました。
    - URL: ${var.health_check_url}
    - 影響: ${var.tenant_id} のみ
  EOT

  tags = merge(
    {
      layer    = "l3"
      tenant   = var.tenant_id
      severity = "high"
    },
    var.tags
  )
}

# L3-Error Monitor
resource "datadog_monitor" "error_logs" {
  name    = "[L3] ${var.tenant_id} エラーログ数"
  type    = "log alert"
  query   = "logs(\"status:error tenant:${var.tenant_id}\").rollup(\"count\").last(\"5m\") > ${var.errors_threshold}"
  message = <<-EOT
    [L3] ${var.tenant_id} のエラーログが5分間で${var.errors_threshold}件を超えました。
    - 影響: ${var.tenant_id} のみ
  EOT

  thresholds = {
    critical = var.errors_threshold
    warning  = var.errors_threshold / 2
  }

  tags = merge(
    {
      layer    = "l3"
      tenant   = var.tenant_id
      severity = "medium"
    },
    var.tags
  )
}

# L3-Latency Monitor（同様に定義）
```

#### outputs.tf（例）

```hcl
output "monitor_ids" {
  description = "L3 Monitor のIDリスト"
  value = {
    health_check = datadog_monitor.health_check.id
    error_logs   = datadog_monitor.error_logs.id
    latency      = datadog_monitor.latency.id
  }
}
```

### 3.4 composite モジュール

#### 責務
- Composite Monitor の作成（L0/L2/L3の親子関係）

#### composites.tf（例）

**重要**: Composite Monitorのクエリ構文は以下のDatadog仕様に従います:
- 論理演算子: `&&` (AND), `||` (OR), `NOT` (否定)
- Monitor ID参照: `${id}` 形式

```hcl
# L0 Composite Monitor
resource "datadog_monitor" "l0_composite" {
  name    = "[L0 Composite] インフラ基盤障害"
  type    = "composite"
  query   = join(" || ", [
    for id in var.l0_monitor_ids : "${id}"
  ])
  message = <<-EOT
    [L0 Composite] インフラ基盤で障害が発生しました。
    - 影響: 全テナント
  EOT

  tags = {
    layer     = "l0"
    composite = "true"
    severity  = "critical"
  }
}

# L2 Composite Monitor
resource "datadog_monitor" "l2_composite" {
  name  = "[L2 Composite] サービスレイヤー障害"
  type  = "composite"
  query = "(${join(" || ", [for id in var.l2_monitor_ids : "${id}"])}) && NOT ${datadog_monitor.l0_composite.id}"
  message = <<-EOT
    [L2 Composite] サービスレイヤーで障害が発生しました。
    注: L0障害中の場合、このアラートは抑制されます。
  EOT

  tags = {
    layer     = "l2"
    composite = "true"
    severity  = "high"
  }
}

# L3 Composite Monitor（テナントごとに for_each で作成）
resource "datadog_monitor" "l3_composite" {
  for_each = var.tenants

  name  = "[L3 Composite] ${each.key} 障害"
  type  = "composite"
  query = "(${join(" || ", [for id in var.l3_monitor_ids[each.key] : "${id}"])}) && NOT ${datadog_monitor.l0_composite.id} && NOT ${datadog_monitor.l2_composite.id}"
  message = <<-EOT
    [L3 Composite] ${each.key} で障害が発生しました。
    - 影響: ${each.key} のみ
    注: L0/L2障害中の場合、このアラートは抑制されます。
  EOT

  tags = {
    layer     = "l3"
    tenant    = each.key
    composite = "true"
    severity  = "medium"
  }
}
```

**修正箇所**:
- `!` → `NOT` に変更（Datadog標準構文）
- Monitor ID参照形式を `${id}` に統一（変数展開との明確化）

## 4. ルートモジュール設計

### 4.1 main.tf（モジュール呼び出し）

```hcl
# L0 インフラ監視モジュール
module "level0_infra" {
  source = "./modules/level0-infra"

  rds_instance_id  = var.rds_instance_id
  ecs_cluster_name = var.ecs_cluster_name
  rds_cpu_threshold = var.rds_cpu_threshold

  tags = var.common_tags
}

# L2 サービス監視モジュール
module "level2_service" {
  source = "./modules/level2-service"

  alb_target_group = var.alb_target_group
  ecs_service_name = var.ecs_service_name

  tags = var.common_tags
}

# L3 テナント監視モジュール（for_each でテナント展開）
module "level3_tenant" {
  for_each = var.tenants
  source   = "./modules/level3-tenant"

  tenant_id          = each.key
  health_check_url   = "https://${var.app_domain}/${each.key}/health"
  errors_threshold   = each.value.errors_threshold
  latency_threshold  = each.value.latency_threshold

  tags = merge(var.common_tags, { tenant = each.key })
}

# Composite Monitor モジュール
module "composite" {
  source = "./modules/composite"

  l0_monitor_ids = module.level0_infra.monitor_ids
  l2_monitor_ids = module.level2_service.monitor_ids
  l3_monitor_ids = {
    for tenant_id, tenant_module in module.level3_tenant :
    tenant_id => tenant_module.monitor_ids
  }
  tenants = var.tenants

  tags = var.common_tags
}
```

### 4.2 variables.tf

```hcl
# Datadog API Key/APP Key（環境変数から注入）
variable "datadog_api_key" {
  description = "Datadog API Key"
  type        = string
  sensitive   = true
}

variable "datadog_app_key" {
  description = "Datadog APP Key"
  type        = string
  sensitive   = true
}

# AWS リソース識別子
variable "rds_instance_id" {
  description = "RDS インスタンス識別子"
  type        = string
}

variable "ecs_cluster_name" {
  description = "ECS Cluster 名"
  type        = string
}

variable "alb_target_group" {
  description = "ALB Target Group 名"
  type        = string
}

variable "ecs_service_name" {
  description = "ECS Service 名"
  type        = string
}

variable "app_domain" {
  description = "アプリケーションドメイン"
  type        = string
}

# 閾値
variable "rds_cpu_threshold" {
  description = "RDS CPU使用率の閾値（%）"
  type        = number
  default     = 95
}

# テナント定義⭐
variable "tenants" {
  description = "テナント定義（テナントID → 閾値）"
  type = map(object({
    errors_threshold  = number
    latency_threshold = number
  }))
}

# 共通タグ
variable "common_tags" {
  description = "全Monitor に付与する共通タグ"
  type        = map(string)
  default     = {
    project     = "datadog-poc"
    environment = "poc"
  }
}
```

### 4.3 terraform.tfvars（Gitにコミットしない）⭐

**重要**: 機密情報管理の明確化

```hcl
# ⚠️ Datadog API Key/APP Key は環境変数で注入（terraform.tfvarsには一切記載しない）
# 実行前に以下の環境変数を設定してください:
#   $env:TF_VAR_datadog_api_key = $env:DD_API_KEY
#   $env:TF_VAR_datadog_app_key = $env:DD_APP_KEY

# AWS リソース識別子
rds_instance_id  = "myapp-db"
ecs_cluster_name = "myapp-cluster"
alb_target_group = "myapp-tg"
ecs_service_name = "myapp-service"
app_domain       = "myapp.example.com"

# 閾値
rds_cpu_threshold = 95

# テナント定義⭐
tenants = {
  tenant-a = {
    errors_threshold  = 10
    latency_threshold = 1000
  }
  tenant-b = {
    errors_threshold  = 10
    latency_threshold = 1000
  }
  tenant-c = {
    errors_threshold  = 10
    latency_threshold = 1000
  }
}

# 共通タグ
common_tags = {
  project     = "datadog-poc"
  environment = "poc"
  managed_by  = "terraform"
}
```

**修正箇所**:
- ファイル冒頭にAPI Key管理方法を明記
- 環境変数注入を明確化（`TF_VAR_*` 形式）

**重要**: このファイルは `.gitignore` に追加し、Gitにコミットしません。

### 4.4 terraform.tfvars.example（Gitにコミット）

```hcl
# このファイルをコピーして terraform.tfvars を作成してください
# cp terraform.tfvars.example terraform.tfvars

# ⚠️ Datadog API Key/APP Key は環境変数で注入してください:
#   $env:TF_VAR_datadog_api_key = $env:DD_API_KEY
#   $env:TF_VAR_datadog_app_key = $env:DD_APP_KEY
# terraform.tfvarsには一切記載しないでください

# AWS リソース識別子（例）
rds_instance_id  = "myapp-db"
ecs_cluster_name = "myapp-cluster"
alb_target_group = "myapp-tg"
ecs_service_name = "myapp-service"
app_domain       = "myapp.example.com"

# テナント定義
tenants = {
  tenant-a = {
    errors_threshold  = 10
    latency_threshold = 1000
  }
}
```

### 4.5 providers.tf

```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    datadog = {
      source  = "DataDog/datadog"
      version = "~> 3.30"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "datadog" {
  api_key = var.datadog_api_key
  app_key = var.datadog_app_key
}

provider "aws" {
  region = "ap-northeast-1"
}
```

### 4.6 backend.tf

```hcl
terraform {
  backend "s3" {
    bucket         = "datadog-terraform-state"
    key            = "datadog-monitors/terraform.tfstate"
    region         = "ap-northeast-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}
```

### 4.7 outputs.tf

```hcl
output "l0_monitor_ids" {
  description = "L0 Monitor のIDリスト"
  value       = module.level0_infra.monitor_ids
}

output "l2_monitor_ids" {
  description = "L2 Monitor のIDリスト"
  value       = module.level2_service.monitor_ids
}

output "l3_monitor_ids" {
  description = "L3 Monitor のIDリスト（テナントごと）"
  value = {
    for tenant_id, tenant_module in module.level3_tenant :
    tenant_id => tenant_module.monitor_ids
  }
}

output "composite_monitor_ids" {
  description = "Composite Monitor のIDリスト"
  value       = module.composite.composite_ids
}
```

## 5. 環境差分管理

### 5.1 PoCでの環境管理

PoCでは1環境（poc）のみのため、terraform.tfvars で管理します。

### 5.2 本番移行時の環境管理（参考）

本番では、環境ごとに terraform.tfvars を分割します。

```
terraform/
├── main.tf
├── variables.tf
├── outputs.tf
├── providers.tf
├── backend.tf
├── modules/
└── environments/
    ├── poc/
    │   └── terraform.tfvars
    ├── staging/
    │   └── terraform.tfvars
    └── production/
        └── terraform.tfvars
```

**デプロイ方法**:

```bash
# PoC環境
terraform apply -var-file=environments/poc/terraform.tfvars

# Staging環境
terraform apply -var-file=environments/staging/terraform.tfvars

# Production環境
terraform apply -var-file=environments/production/terraform.tfvars
```

## 6. テナント追加手順

### 6.1 新規テナント追加（tenant-d を追加する例）

**ステップ1: terraform.tfvars を編集**

```hcl
tenants = {
  tenant-a = {
    errors_threshold  = 10
    latency_threshold = 1000
  }
  tenant-b = {
    errors_threshold  = 10
    latency_threshold = 1000
  }
  tenant-c = {
    errors_threshold  = 10
    latency_threshold = 1000
  }
  tenant-d = {  # ← 追加
    errors_threshold  = 10
    latency_threshold = 1000
  }
}
```

**ステップ2: terraform plan（dry-run）**

```powershell
# 環境変数を設定
$env:TF_VAR_datadog_api_key = $env:DD_API_KEY
$env:TF_VAR_datadog_app_key = $env:DD_APP_KEY

# plan実行
terraform plan -out=tfplan
```

**期待される出力**:

```
Plan: 4 to add, 0 to change, 0 to destroy.

  # module.level3_tenant["tenant-d"] が作成される
  # - L3-Health-tenant-d
  # - L3-Error-tenant-d
  # - L3-Latency-tenant-d
  # module.composite.datadog_monitor.l3_composite["tenant-d"] が作成される
```

**ステップ3: terraform apply**

```powershell
terraform apply tfplan
```

**所要時間**: 5分以内

### 6.2 テナント削除（tenant-c を削除する例）

**ステップ1: terraform.tfvars を編集**

```hcl
tenants = {
  tenant-a = {
    errors_threshold  = 10
    latency_threshold = 1000
  }
  tenant-b = {
    errors_threshold  = 10
    latency_threshold = 1000
  }
  # tenant-c を削除
}
```

**ステップ2: terraform plan → apply**

```powershell
terraform plan -out=tfplan
terraform apply tfplan
```

**期待される出力**:

```
Plan: 0 to add, 0 to change, 4 to destroy.

  # module.level3_tenant["tenant-c"] が削除される
  # module.composite.datadog_monitor.l3_composite["tenant-c"] が削除される
```

## 7. デプロイ手順（dry-run必須）

### 7.1 初回デプロイ

```powershell
# 1. 環境変数を設定
$env:TF_VAR_datadog_api_key = $env:DD_API_KEY
$env:TF_VAR_datadog_app_key = $env:DD_APP_KEY

# 2. Terraform 初期化
terraform init

# 3. plan（dry-run）
terraform plan -out=tfplan

# 4. 確認後、apply
terraform apply tfplan
```

### 7.2 変更デプロイ

```powershell
# terraform.tfvars を編集後

# 1. plan（dry-run）
terraform plan -out=tfplan

# 2. 差分を確認
# ✅ 追加・変更のみであることを確認
# ❌ 意図しない削除がないことを確認

# 3. apply
terraform apply tfplan
```

### 7.3 削除（PoC終了時）

```powershell
# ⚠️ 全ての Monitor を削除
terraform destroy
```

**注**: 本番環境では `terraform destroy` は原則禁止。

## 8. Workspace管理（オプション）

### 8.1 Workspace を使用する場合

```bash
# Workspace作成
terraform workspace new poc
terraform workspace new staging
terraform workspace new production

# Workspace切り替え
terraform workspace select poc

# 現在のWorkspace確認
terraform workspace show
```

### 8.2 Workspace別の変数管理

```hcl
# variables.tf
variable "environment" {
  description = "環境名"
  type        = string
  default     = terraform.workspace
}
```

**注**: PoCではWorkspace不要。本番移行時に検討。

## 9. 実装者向けガイド

### 9.1 実装開始時に参照すべきドキュメント

| ドキュメント | パス | 目的 |
|------------|------|------|
| Terraform技術標準 | .claude/docs/40_standards/42_infra/iac/terraform.md | ベストプラクティス |
| 監視設計 | docs/04_インフラ設計/01_基本設計/05_監視設計.md | Monitor定義の仕様 |
| セキュリティ設計 | docs/04_インフラ設計/01_基本設計/03_セキュリティ設計.md | API Key管理 |
| このドキュメント | docs/04_インフラ設計/01_基本設計/10_IaC方針.md | ディレクトリ構成 |

### 9.2 サンプルコード

Datadog Provider の公式ドキュメント:
- https://registry.terraform.io/providers/DataDog/datadog/latest/docs

**参考**: Composite Monitor の実装例
- https://registry.terraform.io/providers/DataDog/datadog/latest/docs/resources/monitor#composite-monitor

## 10. トラブルシューティング

### 10.1 よくあるエラー

| エラー | 原因 | 対処 |
|------|------|------|
| `Error: Invalid provider credentials` | Datadog API Key/APP Key が未設定 | 環境変数 `TF_VAR_datadog_api_key` を設定 |
| `Error: Backend initialization required` | backend.tf の S3バケットが存在しない | S3バケットを作成（06_バックアップ設計.md参照） |
| `Error: DynamoDB table not found` | State Lock のテーブルが存在しない | DynamoDBテーブルを作成（06_バックアップ設計.md参照） |
| `Error: Monitor already exists` | 手動作成したMonitorと名前が重複 | 既存Monitorを削除、または terraform import |

### 10.2 デバッグ方法

```powershell
# Terraform ログレベルを DEBUG に設定
$env:TF_LOG = "DEBUG"
terraform plan

# ログをファイルに保存
terraform plan 2>&1 | Out-File -FilePath terraform-debug.log
```

## 11. CI/CD統合（本番推奨）

### 11.1 GitHub Actions 例（参考）

```yaml
# .github/workflows/terraform.yml
name: Terraform CI/CD

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  terraform:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v2
        with:
          terraform_version: 1.5.0

      - name: Terraform Init
        run: terraform init
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}

      - name: Terraform Plan
        run: terraform plan -out=tfplan
        env:
          TF_VAR_datadog_api_key: ${{ secrets.DATADOG_API_KEY }}
          TF_VAR_datadog_app_key: ${{ secrets.DATADOG_APP_KEY }}

      - name: Terraform Apply（mainブランチのみ）
        if: github.ref == 'refs/heads/main'
        run: terraform apply tfplan
```

**注**: PoCではCI/CD不要。本番移行時に導入推奨。

## 12. 関連ドキュメント

| ドキュメント | パス |
|-------------|------|
| システム構成図 | [01_システム構成図.md](01_システム構成図.md) |
| セキュリティ設計 | [03_セキュリティ設計.md](03_セキュリティ設計.md) |
| 監視設計 | [05_監視設計.md](05_監視設計.md) |
| バックアップ設計 | [06_バックアップ設計.md](06_バックアップ設計.md) |
| Terraform技術標準 | .claude/docs/40_standards/42_infra/iac/terraform.md |

---

**作成日**: 2025-12-28
**作成者**: Infra-Architect
**バージョン**: 1.1
**ステータス**: Draft
**重要度**: ★★★★★（実装の基盤）
**変更履歴**:
- 1.1 (2025-12-28): Composite Monitorクエリ構文修正（`!` → `NOT`）、terraform.tfvars機密情報管理明確化
