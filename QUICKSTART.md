# クイックスタートガイド

**所要時間**: 約30分
**コスト**: 1日約$1.8、1週間約$13

---

## 事前準備（5分）

```bash
# 1. 環境変数設定
export DD_API_KEY="your-datadog-api-key"
export DD_APP_KEY="your-datadog-app-key"
export AWS_PROFILE="your-aws-profile"

# 2. リポジトリルートに移動
cd c:\dev2\datadog-fro-AWS-terraform

# 3. Backend作成（初回のみ）
./scripts/setup-backend.sh datadog-poc-terraform-state

# 確認
aws s3 ls s3://datadog-poc-terraform-state
aws dynamodb describe-table --table-name datadog-poc-terraform-state-lock --region ap-northeast-1
```

---

## AWS基盤デプロイ（15分）

```bash
cd infra/terraform/aws

# 初期化
terraform init

# Plan確認（差分チェック）
terraform plan -var-file=../shared/tenants.tfvars -var="dd_api_key=${DD_API_KEY}" -out=tfplan

# Apply実行
terraform apply tfplan

# 完了確認
terraform output
```

**待機**: RDS作成に10〜15分かかります。コーヒーブレイク推奨。

---

## Datadog監視デプロイ（5分）

```bash
cd ../datadog

# 初期化
terraform init

# Plan確認
terraform plan -var-file=../shared/tenants.tfvars -out=tfplan

# Apply実行
terraform apply tfplan

# 完了確認
terraform output
```

---

## 動作確認（5分）

```bash
# ALB URL取得
cd ../aws
ALB_URL=$(terraform output -raw alb_dns_name)

# ヘルスチェック（全テナント）
curl http://${ALB_URL}/tenant-a/health
curl http://${ALB_URL}/tenant-b/health
curl http://${ALB_URL}/tenant-c/health
```

**期待される出力**:
```json
{"status":"ok","tenant":"tenant-a","timestamp":"2025-12-29T..."}
```

**Datadogダッシュボード確認**:
https://app.datadoghq.com/dashboard/lists

---

## 検証終了後: リソース削除

```bash
# 1. Datadog削除
cd infra/terraform/datadog
terraform destroy -var-file=../shared/tenants.tfvars

# 2. AWS削除
cd ../aws
terraform destroy -var-file=../shared/tenants.tfvars -var="dd_api_key=${DD_API_KEY}"

# 3. Backend削除（オプション）
aws s3 rb s3://datadog-poc-terraform-state --force
aws dynamodb delete-table --table-name datadog-poc-terraform-state-lock --region ap-northeast-1
```

---

## トラブルシューティング

### ECSタスクが起動しない

```bash
# ECSタスク確認
CLUSTER=$(cd infra/terraform/aws && terraform output -raw ecs_cluster_name)
aws ecs list-tasks --cluster ${CLUSTER}

# ログ確認
aws logs tail /ecs/demo-api --follow
```

### curlが失敗する

**原因1**: ECSタスク起動待ち
- 対処: 3〜5分待ってから再試行

**原因2**: セキュリティグループ設定
- 対処: AWSコンソールでALBセキュリティグループを確認

---

## 詳細ドキュメント

- 詳しいデプロイ手順: [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md)
- アーキテクチャ: [README.md](README.md)
- テナント追加: [docs/adding-tenant.md](docs/adding-tenant.md)
