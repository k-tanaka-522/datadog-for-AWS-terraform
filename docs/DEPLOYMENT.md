# AWS基盤 Terraform デプロイ手順書

**プロジェクト**: Datadog + ECS マルチテナント監視デモ
**環境**: 検証用（検証終了後にdestroy予定）
**作成日**: 2025-12-29

---

## 前提条件

### 必須ツール

- AWS CLI v2 以上
- Terraform >= 1.5
- Docker / Docker Compose（ローカル確認用）
- jq（オプション、JSON整形用）

### AWS認証情報

```bash
# AWS CLIプロファイル設定（未設定の場合）
aws configure --profile your-profile

# または、環境変数で設定
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="ap-northeast-1"

# プロファイル指定
export AWS_PROFILE="your-profile"
```

### Datadog認証情報

```bash
# Datadog APIキー取得
# https://app.datadoghq.com/organization-settings/api-keys

export DD_API_KEY="your-datadog-api-key"
export DD_APP_KEY="your-datadog-app-key"
```

**重要**: これらの環境変数は削除まで保持してください（destroy時にも必要）

---

## フェーズ1: Terraform Backend準備

### 1.1 Backend作成

```bash
# リポジトリルートで実行
cd c:\dev2\datadog-fro-AWS-terraform

# S3バケット + DynamoDBテーブル作成
./scripts/setup-backend.sh datadog-poc-terraform-state
```

### 1.2 作成確認

```bash
# S3バケット確認
aws s3 ls s3://datadog-poc-terraform-state

# DynamoDBテーブル確認
aws dynamodb describe-table \
  --table-name datadog-poc-terraform-state-lock \
  --region ap-northeast-1 \
  --query 'Table.[TableName,TableStatus]' \
  --output text
```

**期待される出力**:
```
datadog-poc-terraform-state-lock    ACTIVE
```

---

## フェーズ2: AWS基盤デプロイ

### 2.1 ディレクトリ移動

```bash
cd infra/terraform/aws
```

### 2.2 Terraform初期化

```bash
terraform init
```

**期待される出力**:
```
Initializing the backend...
Successfully configured the backend "s3"!
...
Terraform has been successfully initialized!
```

### 2.3 Plan実行（差分確認）

```bash
terraform plan \
  -var-file=../shared/tenants.tfvars \
  -var="dd_api_key=${DD_API_KEY}" \
  -out=tfplan
```

**確認ポイント**:
- 作成されるリソース数（Plan: X to add, 0 to change, 0 to destroy）
- VPC, Subnet, RDS, ECS, ALB等の主要リソースが含まれているか
- エラーがないか

### 2.4 Apply実行

```bash
# dry-runで問題なければ本番実行
terraform apply tfplan
```

**所要時間**: 約10〜15分（RDS作成に時間がかかります）

### 2.5 デプロイ確認

```bash
# 出力値確認
terraform output

# ALB URL取得
ALB_URL=$(terraform output -raw alb_dns_name)
echo "ALB URL: http://${ALB_URL}"

# RDS Endpoint確認
terraform output rds_endpoint

# ECS Cluster名確認
terraform output ecs_cluster_name
```

### 2.6 動作確認

```bash
# ALB経由でヘルスチェック（ECSタスク起動まで数分待つ）
curl http://${ALB_URL}/tenant-a/health
curl http://${ALB_URL}/tenant-b/health
curl http://${ALB_URL}/tenant-c/health
```

**期待される出力** (各テナント):
```json
{
  "status": "ok",
  "tenant": "tenant-a",
  "timestamp": "2025-12-29T..."
}
```

**エラーの場合**:
- ECSタスクの起動状態を確認:
  ```bash
  aws ecs list-tasks --cluster $(terraform output -raw ecs_cluster_name)
  ```
- CloudWatch Logsでアプリケーションログを確認:
  ```bash
  aws logs tail /ecs/demo-api --follow
  ```

---

## フェーズ3: Datadog監視デプロイ

### 3.1 ディレクトリ移動

```bash
cd ../datadog
```

### 3.2 Terraform初期化

```bash
terraform init
```

### 3.3 Plan実行

```bash
terraform plan \
  -var-file=../shared/tenants.tfvars \
  -out=tfplan
```

**確認ポイント**:
- Datadog Monitor（Level 0, 2, 3）が作成されるか
- Composite Monitorが作成されるか
- Dashboard が作成されるか

### 3.4 Apply実行

```bash
terraform apply tfplan
```

**所要時間**: 約2〜3分

### 3.5 Datadog確認

```bash
# ブラウザで以下を確認
# - Dashboard: https://app.datadoghq.com/dashboard/lists
# - Monitor: https://app.datadoghq.com/monitors/manage

# CLI で Monitor ID を確認
terraform output
```

---

## フェーズ4: 総合動作確認

### 4.1 負荷テスト（オプション）

```bash
# 10秒間、10並列リクエスト
for i in {1..100}; do
  curl -s http://${ALB_URL}/tenant-a/health &
done
wait

# Datadogでメトリクスが上がっているか確認
```

### 4.2 アラートテスト（オプション）

```bash
# わざとエラーを発生させる（存在しないエンドポイント）
curl http://${ALB_URL}/tenant-a/error

# Datadogでアラートが発火するか確認（5〜10分後）
```

---

## トラブルシューティング

### Backend初期化エラー

**症状**:
```
Error: Failed to get existing workspaces: S3 bucket does not exist.
```

**対処**:
```bash
# Backend再作成
./scripts/setup-backend.sh datadog-poc-terraform-state
cd infra/terraform/aws
terraform init -reconfigure
```

### Apply中のタイムアウト

**症状**:
```
Error: timeout while waiting for state to become 'available'
```

**対処**:
- RDS作成に時間がかかる場合があります（15分以上かかることもある）
- AWSコンソールでRDSの状態を確認:
  ```bash
  aws rds describe-db-instances \
    --db-instance-identifier demo-postgres \
    --query 'DBInstances[0].DBInstanceStatus'
  ```

### ECSタスクが起動しない

**症状**:
```
curl: (7) Failed to connect to xxx port 80: Connection refused
```

**対処**:
```bash
# ECSタスク状態確認
CLUSTER=$(cd infra/terraform/aws && terraform output -raw ecs_cluster_name)
aws ecs list-tasks --cluster ${CLUSTER}

# タスク詳細確認
TASK_ARN=$(aws ecs list-tasks --cluster ${CLUSTER} --query 'taskArns[0]' --output text)
aws ecs describe-tasks --cluster ${CLUSTER} --tasks ${TASK_ARN}

# CloudWatch Logs確認
aws logs tail /ecs/demo-api --follow
```

**よくある原因**:
- ECRイメージがpushされていない → `docker push` を実行
- セキュリティグループでポート80が許可されていない → Terraformコード確認
- RDSエンドポイントが解決できない → VPC DNS設定確認

---

## 検証終了後のリソース削除

**重要**: このプロジェクトは検証用です。検証終了後は必ずリソースを削除してください。

### Step 1: Datadog監視削除

```bash
cd infra/terraform/datadog
terraform destroy -var-file=../shared/tenants.tfvars
```

**確認**:
```
Plan: 0 to add, 0 to change, X to destroy.

Do you really want to destroy all resources?
  Enter a value: yes
```

### Step 2: AWSインフラ削除

```bash
cd ../aws
terraform destroy \
  -var-file=../shared/tenants.tfvars \
  -var="dd_api_key=${DD_API_KEY}"
```

**所要時間**: 約10分（RDS削除に時間がかかる）

**確認ポイント**:
- ECS Service停止 → Task停止 → ALB削除 → RDS削除の順に処理される
- エラーが出た場合は、AWSコンソールで残存リソースを確認

### Step 3: Backend削除（オプション）

**注意**: Stateファイルが完全に不要な場合のみ実行

```bash
# S3バケット削除
aws s3 rb s3://datadog-poc-terraform-state --force

# DynamoDBテーブル削除
aws dynamodb delete-table \
  --table-name datadog-poc-terraform-state-lock \
  --region ap-northeast-1
```

### Step 4: 残存リソース確認

```bash
# ECRリポジトリ確認（イメージは自動削除されない）
aws ecr describe-repositories --repository-names demo-api

# 必要に応じて削除
aws ecr delete-repository --repository-name demo-api --force

# RDSスナップショット確認（自動作成されている場合）
aws rds describe-db-snapshots --query 'DBSnapshots[?starts_with(DBSnapshotIdentifier, `demo-postgres`)].DBSnapshotIdentifier'

# 不要であれば削除
aws rds delete-db-snapshot --db-snapshot-identifier <snapshot-id>
```

---

## チェックリスト

### デプロイ前

- [ ] AWS認証情報設定完了（AWS_PROFILE or AWS_ACCESS_KEY_ID）
- [ ] Datadog認証情報設定完了（DD_API_KEY, DD_APP_KEY）
- [ ] Terraform Backend作成完了
- [ ] backend.tfのバケット名確認（datadog-poc-terraform-state）

### デプロイ後

- [ ] `terraform output` で全リソース確認
- [ ] ALB経由でヘルスチェック成功（全テナント）
- [ ] Datadogダッシュボードにメトリクス表示
- [ ] Datadog Monitorが正常作成

### 削除後

- [ ] Datadog監視削除完了（terraform destroy成功）
- [ ] AWSインフラ削除完了（terraform destroy成功）
- [ ] 残存リソース確認（ECR, RDSスナップショット等）
- [ ] Backend削除（オプション、不要な場合のみ）

---

## 参考情報

### コスト概算

| リソース | 月額（東京リージョン） |
|---------|---------------------|
| RDS db.t4g.micro | $12 |
| ECS Fargate (3 tasks x 0.25vCPU x 0.5GB) | $20 |
| ALB | $20 |
| ECR, Secrets Manager | $2 |
| **合計** | **約 $55/月** |

**時間課金**: 1日稼働で約 $1.8
**1週間検証**: 約 $13

### State ファイル管理

- **AWS**: `s3://datadog-poc-terraform-state/aws/terraform.tfstate`
- **Datadog**: `s3://datadog-poc-terraform-state/datadog/terraform.tfstate`

State分離により、AWS/Datadog を独立してデプロイ・削除可能。

### 関連ドキュメント

- [テナント追加手順](adding-tenant.md)
- [監視設計](monitoring-design.md)
- [Terraform State管理](terraform-state.md)
- [アーキテクチャ設計](architecture.md)

---

**作成者**: SRE
**最終更新**: 2025-12-29
