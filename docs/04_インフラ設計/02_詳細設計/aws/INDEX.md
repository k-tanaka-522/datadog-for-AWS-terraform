# AWS基盤 Terraform 設計書 INDEX

## プロジェクト概要

| 項目 | 内容 |
|------|------|
| プロジェクト名 | Datadog for AWS Terraform PoC |
| 目的 | AWS検証アカウントに新規環境をTerraformで構築 |
| スコープ | VPC, ECS(Fargate), RDS, ALB, ECR, IAM, CloudWatch |
| IaCツール | Terraform v1.5+ |

## 設計方針

### 新規構築の理由

**PMからの確認結果**:
- AWS検証アカウントは存在するが、リソースは未構築状態
- 既存環境を利用する前提（基本設計）から、**新規構築**に変更

### マルチテナント対応

- **for_each パターン**: `var.tenants` でテナントリソースを管理
- テナント追加時は tfvars に1行追加 → `terraform apply`

### コスト最適化（検証環境）

- Fargate: Spot 未使用（検証環境のため安定性優先）
- RDS: t4g.micro（最小インスタンス）
- NAT Gateway: **不要**（Fargate を Public Subnet 配置）

## ドキュメント構成

| ドキュメント | 概要 | ステータス |
|------------|------|----------|
| [01_VPC設計.md](01_VPC設計.md) | VPC, Subnet, Route Table, Security Group | 🔄 作成中 |
| [02_ECS設計.md](02_ECS設計.md) | ECS Cluster, Service, Task Definition | 🔄 作成中 |
| [03_ALB設計.md](03_ALB設計.md) | ALB, Target Group, Listener | 🔄 作成中 |
| [04_RDS設計.md](04_RDS設計.md) | RDS PostgreSQL（Multi-AZ） | 🔄 作成中 |
| [05_ECR設計.md](05_ECR設計.md) | ECR Repository（脆弱性スキャン） | 🔄 作成中 |
| [06_IAM設計.md](06_IAM設計.md) | ECS Task Role, Execution Role | 🔄 作成中 |
| [07_CloudWatch設計.md](07_CloudWatch設計.md) | CloudWatch Logs, VPC Flow Logs | 🔄 作成中 |

## 技術スタック

| レイヤー | 技術 |
|--------|------|
| IaC | Terraform v1.5+ |
| コンテナオーケストレーション | ECS Fargate（Public Subnet） |
| ロードバランサー | ALB |
| データベース | RDS PostgreSQL 16.x（Multi-AZ） |
| コンテナレジストリ | ECR（脆弱性スキャン有効） |
| ログ管理 | CloudWatch Logs |
| State管理 | S3 + DynamoDB |

## ディレクトリ構成（実装時の目標）

```
terraform/aws/
├── main.tf              # メイン設定
├── variables.tf         # 変数定義
├── providers.tf         # Provider設定（AWS）
├── backend.tf           # S3 Backend設定
├── outputs.tf           # 出力値
├── vpc.tf               # VPC, Subnet, Route Table, SG
├── ecs.tf               # ECS Cluster, Service, Task Definition
├── alb.tf               # ALB, Target Group, Listener
├── rds.tf               # RDS PostgreSQL
├── ecr.tf               # ECR Repository
├── iam.tf               # ECS Task Role, Execution Role
└── cloudwatch.tf        # CloudWatch Logs, VPC Flow Logs
```

**重要な設計判断**:
- **ファイル分割**: リソースタイプごとに分割（vpc.tf, ecs.tf...）
- **モジュール化なし**: 検証環境のため、シンプルな構成を優先
- **for_each**: テナント関連リソース（ECS Service, Target Group等）に適用

## テナント構成

### 初期テナント（tfvarsで定義）

```hcl
tenants = {
  tenant-a = {
    name   = "tenant-a"
    cpu    = 256
    memory = 512
  }
  tenant-b = {
    name   = "tenant-b"
    cpu    = 256
    memory = 512
  }
  tenant-c = {
    name   = "tenant-c"
    cpu    = 256
    memory = 512
  }
}
```

### テナント追加手順

1. `terraform/shared/tenants.tfvars` に1行追加
2. `terraform plan -var-file=../shared/tenants.tfvars`（dry-run）
3. `terraform apply -var-file=../shared/tenants.tfvars`

## 重要な設計判断（ADR）

### ADR-AWS-001: Fargate を Public Subnet に配置

**決定**: Fargate タスクを Public Subnet に配置し、NAT Gateway を使用しない

**理由**:
- 検証環境のため、NAT Gateway コスト（$32.4/月）を削減
- Public Subnet + Public IP 割り当てで Datadog API 通信可能
- Security Group で Inbound 制限、実質的なセキュリティ確保

**トレードオフ**:
- Public IP が割り当てられる（本番環境では Private Subnet + NAT Gateway 推奨）
- Security Group で厳密な制御が必要

### ADR-AWS-002: RDS は t4g.micro（Multi-AZ）

**決定**: RDS PostgreSQL 16.x、t4g.micro、Multi-AZ

**理由**:
- 検証環境のため、最小インスタンスタイプ
- Multi-AZ は Datadog L0 監視検証のため必須

**トレードオフ**:
- t4g.micro は性能制限があるが、検証用途では十分

### ADR-AWS-003: モジュール化せず、フラットな構成

**決定**: `terraform/aws/` にフラットにリソースを配置

**理由**:
- 検証環境のため、シンプルさを優先
- modules/ ディレクトリは作成せず、リソースタイプごとにファイル分割

**トレードオフ**:
- 再利用性は低いが、検証環境では許容

## State管理

### S3 Backend

```hcl
terraform {
  backend "s3" {
    bucket         = "datadog-poc-terraform-state"
    key            = "aws/terraform.tfstate"
    region         = "ap-northeast-1"
    encrypt        = true
    dynamodb_table = "datadog-poc-terraform-lock"
  }
}
```

### 初期化手順

```bash
# Backend用リソース作成（初回のみ）
./scripts/setup-backend.sh datadog-poc-terraform-state

# Terraform 初期化
cd terraform/aws
terraform init
```

## セキュリティ考慮事項

| 項目 | 設計 |
|------|------|
| RDS 暗号化 | 有効（KMS デフォルトキー） |
| RDS SSL/TLS | 必須（require_ssl パラメータグループ） |
| ECR 脆弱性スキャン | 有効（push時に自動スキャン） |
| CloudWatch Logs 暗号化 | 有効（デフォルト） |
| Datadog API Key 管理 | 環境変数（`DD_API_KEY`）、ハードコード禁止 |

## 環境変数（必須）

```bash
export DD_API_KEY="your-datadog-api-key"
export DD_APP_KEY="your-datadog-app-key"  # Datadog Terraform 用
export AWS_PROFILE="your-aws-profile"
export AWS_REGION="ap-northeast-1"
```

## デプロイ手順

```bash
# 1. Backend 初期化（初回のみ）
./scripts/setup-backend.sh datadog-poc-terraform-state

# 2. AWS インフラデプロイ
cd terraform/aws
terraform init
terraform plan -var-file=../shared/tenants.tfvars -var="dd_api_key=${DD_API_KEY}"
terraform apply -var-file=../shared/tenants.tfvars -var="dd_api_key=${DD_API_KEY}"

# 3. ECR へイメージプッシュ
cd ../../app
docker build -t demo-api .
aws ecr get-login-password --region ap-northeast-1 | docker login --username AWS --password-stdin <ECR_URI>
docker tag demo-api:latest <ECR_URI>/demo-api:latest
docker push <ECR_URI>/demo-api:latest

# 4. ECS タスク起動確認
aws ecs list-tasks --cluster datadog-poc-cluster --region ap-northeast-1
```

## 関連ドキュメント

| ドキュメント | パス |
|-------------|------|
| 基本設計 INDEX | ../../01_基本設計/INDEX.md |
| Terraform 技術標準 | ../../../../.claude/docs/40_standards/42_infra/iac/terraform.md |
| セキュリティ基準 | ../../../../.claude/docs/40_standards/49_common/security.md |
| 要件定義書 | ../../../02_要件定義/要件定義書.md |

---

**作成日**: 2025-12-29
**作成者**: Infra-Architect
**バージョン**: 1.0
**ステータス**: Draft
