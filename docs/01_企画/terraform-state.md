# Terraform State 管理

## 概要

Terraform は現在のインフラ状態を「State ファイル」で管理する。
このファイルを適切に管理しないと、以下の問題が発生する:

- 複数人での作業時にコンフリクト
- State ファイル紛失でインフラ管理不能
- 機密情報（パスワード等）の漏洩リスク

## State の保存場所

### ローカル (デフォルト・非推奨)

```
terraform/aws/
├── terraform.tfstate      ← State ファイル
├── terraform.tfstate.backup
└── main.tf
```

問題点:
- Git に含めると機密情報漏洩
- .gitignore すると共有できない
- PC故障で消失

### リモート Backend (推奨)

```
┌─────────────────┐
│   S3 Bucket     │ ← State ファイル保存
│   (暗号化)      │
└────────┬────────┘
         │
┌────────┴────────┐
│  DynamoDB Table │ ← ロック管理 (同時実行防止)
└─────────────────┘
```

## 本プロジェクトの設定

### Backend 設定ファイル

```hcl
# terraform/aws/backend.tf

terraform {
  backend "s3" {
    bucket         = "your-tfstate-bucket"        # 要変更
    key            = "datadog-ecs-demo/aws/terraform.tfstate"
    region         = "ap-northeast-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"       # オプション
  }
}
```

```hcl
# terraform/datadog/backend.tf

terraform {
  backend "s3" {
    bucket         = "your-tfstate-bucket"        # 同じバケット
    key            = "datadog-ecs-demo/datadog/terraform.tfstate"  # 別キー
    region         = "ap-northeast-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}
```

### 初期セットアップ

```bash
# 1. S3 バケット作成
aws s3 mb s3://your-tfstate-bucket --region ap-northeast-1

# 2. バージョニング有効化 (誤削除対策)
aws s3api put-bucket-versioning \
  --bucket your-tfstate-bucket \
  --versioning-configuration Status=Enabled

# 3. 暗号化設定
aws s3api put-bucket-encryption \
  --bucket your-tfstate-bucket \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

# 4. (オプション) DynamoDB テーブル作成 (ロック用)
aws dynamodb create-table \
  --table-name terraform-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region ap-northeast-1
```

または、セットアップスクリプトを使用:

```bash
./scripts/setup-backend.sh your-tfstate-bucket
```

## AWS と Datadog で State を分ける理由

```
terraform/
├── aws/
│   └── terraform.tfstate     ← AWS リソースの状態
│
└── datadog/
    └── terraform.tfstate     ← Datadog リソースの状態
```

メリット:
- AWS 変更時に Datadog 側を壊すリスクなし
- 監視設定だけ変更する場合に高速
- チーム分担しやすい (インフラ担当 / SRE担当)

## State 間の連携

Datadog 側から AWS 側の情報を参照する:

```hcl
# terraform/datadog/data.tf

data "terraform_remote_state" "aws" {
  backend = "s3"
  
  config = {
    bucket = "your-tfstate-bucket"
    key    = "datadog-ecs-demo/aws/terraform.tfstate"
    region = "ap-northeast-1"
  }
}

# 使用例
locals {
  rds_identifier = data.terraform_remote_state.aws.outputs.rds_identifier
  alb_dns        = data.terraform_remote_state.aws.outputs.alb_dns_name
}
```

## よくある操作

### State の確認

```bash
# リソース一覧
terraform state list

# 特定リソースの詳細
terraform state show aws_ecs_service.tenant["acme"]
```

### State のリフレッシュ

実際のAWS状態と同期:

```bash
terraform refresh -var-file=../shared/tenants.tfvars
```

### State からリソース削除 (実リソースは残す)

```bash
# Terraform 管理から外す (実リソースは削除しない)
terraform state rm aws_ecs_service.tenant["acme"]
```

### State のインポート

既存リソースを Terraform 管理下に:

```bash
terraform import aws_db_instance.main demo-multitenant-pg
```

## トラブルシューティング

### State ロックが解除されない

```bash
# ロック強制解除 (他の人が実行中でないことを確認)
terraform force-unlock LOCK_ID
```

### State が破損した

```bash
# S3 バージョニングから復元
aws s3api list-object-versions --bucket your-tfstate-bucket \
  --prefix datadog-ecs-demo/aws/terraform.tfstate

aws s3api get-object --bucket your-tfstate-bucket \
  --key datadog-ecs-demo/aws/terraform.tfstate \
  --version-id VERSION_ID \
  terraform.tfstate.recovered
```

## セキュリティ

### S3 バケットポリシー例

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::your-tfstate-bucket",
        "arn:aws:s3:::your-tfstate-bucket/*"
      ],
      "Condition": {
        "Bool": {
          "aws:SecureTransport": "false"
        }
      }
    }
  ]
}
```

### アクセス制限

State ファイルには機密情報が含まれる可能性があるため:

- S3 バケットへのアクセスは最小限に
- IAM ポリシーで terraform 実行者のみに制限
- CloudTrail で操作ログを記録
