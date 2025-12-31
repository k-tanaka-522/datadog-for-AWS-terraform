# Claude Code 実装指示書

## プロジェクト概要

Datadog + AWS ECS マルチテナント監視のデモ環境を Terraform で構築する。

### ゴール

1. テナント追加時に `tenants.tfvars` 編集 → `terraform apply` だけで AWS リソースと Datadog 監視が自動作成される
2. Composite Monitor で親子関係を実装し、インフラ障害時にアプリアラートを抑制する
3. ローカル開発環境 (docker-compose) で動作確認できる

---

## ディレクトリ構成

```
datadog-ecs-demo/
├── app/                        # FastAPI アプリケーション
│   ├── main.py
│   ├── database.py
│   ├── schemas.py
│   ├── requirements.txt
│   ├── Dockerfile
│   └── docker-compose.yml      # ローカル開発用
│
├── terraform/
│   ├── shared/
│   │   └── tenants.tfvars      # テナント定義
│   │
│   ├── aws/                    # AWS インフラ
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── versions.tf
│   │   ├── backend.tf
│   │   ├── outputs.tf
│   │   │
│   │   ├── network/
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   ├── outputs.tf
│   │   │   ├── vpc.tf
│   │   │   ├── subnets.tf      # Public のみ (NAT なし)
│   │   │   └── security_groups.tf
│   │   │
│   │   ├── database/
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   ├── outputs.tf
│   │   │   ├── rds.tf
│   │   │   ├── parameter_group.tf
│   │   │   └── secrets.tf
│   │   │
│   │   ├── compute/
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   ├── outputs.tf
│   │   │   ├── cluster.tf
│   │   │   ├── task_definition.tf  # for_each tenants
│   │   │   ├── service.tf          # for_each tenants
│   │   │   ├── iam.tf
│   │   │   └── logs.tf
│   │   │
│   │   ├── loadbalancer/
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   ├── outputs.tf
│   │   │   ├── alb.tf
│   │   │   ├── target_groups.tf    # for_each tenants
│   │   │   └── listener_rules.tf   # for_each tenants
│   │   │
│   │   ├── ecr/
│   │   │   ├── main.tf
│   │   │   └── outputs.tf
│   │   │
│   │   └── datadog/
│   │       ├── main.tf
│   │       ├── iam.tf              # AWS Integration 用 IAM Role
│   │       └── secrets.tf          # DD_API_KEY
│   │
│   └── datadog/                # Datadog 監視
│       ├── main.tf
│       ├── variables.tf
│       ├── versions.tf
│       ├── backend.tf
│       ├── data.tf                 # AWS remote_state 参照
│       ├── integration.tf          # AWS Integration
│       ├── outputs.tf
│       │
│       ├── monitoring/
│       │   ├── main.tf             # モジュール呼び出し
│       │   ├── variables.tf
│       │   │
│       │   └── modules/
│       │       ├── level0-infra/
│       │       │   ├── main.tf
│       │       │   ├── variables.tf
│       │       │   ├── outputs.tf
│       │       │   ├── rds.tf
│       │       │   └── ecs.tf
│       │       │
│       │       ├── level2-health/
│       │       │   ├── main.tf
│       │       │   ├── variables.tf
│       │       │   ├── outputs.tf
│       │       │   └── synthetics.tf
│       │       │
│       │       ├── level3-tenant/
│       │       │   ├── main.tf
│       │       │   ├── variables.tf
│       │       │   ├── outputs.tf
│       │       │   ├── logs.tf
│       │       │   ├── metrics.tf
│       │       │   └── latency.tf
│       │       │
│       │       └── composite/
│       │           ├── main.tf
│       │           ├── variables.tf
│       │           └── outputs.tf
│       │
│       └── dashboards/
│           ├── main.tf
│           └── modules/
│               └── tenant-dashboard/
│
├── scripts/
│   ├── setup-backend.sh
│   ├── deploy-aws.sh
│   ├── deploy-datadog.sh
│   └── destroy-all.sh
│
└── docs/                       # 作成済み
    ├── terraform-state.md
    ├── adding-tenant.md
    ├── monitoring-design.md
    ├── synthetics.md
    └── architecture.md
```

---

## 実装詳細

### 1. app/ - FastAPI アプリケーション

#### main.py

```python
from fastapi import FastAPI, Path, HTTPException
from database import get_db_pool
import structlog

logger = structlog.get_logger()
app = FastAPI()

@app.get("/{tenant_id}/health")
async def health(tenant_id: str = Path(..., regex="^[a-z0-9-]+$")):
    """
    ヘルスチェック - DB疎通まで確認
    Datadog Synthetics / ALB HealthCheck で使用
    """
    pool = await get_db_pool()
    async with pool.acquire() as conn:
        await conn.execute(f"SELECT 1 FROM {tenant_id}.health_check")
    
    logger.info("health_check", tenant_id=tenant_id, status="ok")
    return {"status": "ok", "tenant": tenant_id}

@app.get("/{tenant_id}/items")
async def get_items(tenant_id: str = Path(...)):
    """アイテム一覧取得"""
    pool = await get_db_pool()
    async with pool.acquire() as conn:
        rows = await conn.fetch(f"SELECT * FROM {tenant_id}.items ORDER BY id")
    
    logger.info("get_items", tenant_id=tenant_id, count=len(rows))
    return {"tenant": tenant_id, "items": [dict(r) for r in rows]}

@app.post("/{tenant_id}/items")
async def create_item(tenant_id: str, name: str):
    """アイテム作成"""
    pool = await get_db_pool()
    async with pool.acquire() as conn:
        row = await conn.fetchrow(
            f"INSERT INTO {tenant_id}.items (name) VALUES ($1) RETURNING *",
            name
        )
    
    logger.info("create_item", tenant_id=tenant_id, item_id=row["id"])
    return {"tenant": tenant_id, "item": dict(row)}
```

#### database.py

```python
import os
import asyncpg

_pool = None

async def get_db_pool():
    global _pool
    if _pool is None:
        _pool = await asyncpg.create_pool(
            host=os.getenv("DB_HOST", "localhost"),
            port=int(os.getenv("DB_PORT", 5432)),
            user=os.getenv("DB_USER", "postgres"),
            password=os.getenv("DB_PASSWORD", "postgres"),
            database=os.getenv("DB_NAME", "demo"),
            min_size=2,
            max_size=10,
        )
    return _pool
```

#### requirements.txt

```
fastapi==0.109.0
uvicorn==0.27.0
asyncpg==0.29.0
structlog==24.1.0
```

#### Dockerfile

```dockerfile
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8080

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
```

#### docker-compose.yml

```yaml
version: '3.8'

services:
  api:
    build: .
    ports:
      - "8080:8080"
    environment:
      - DB_HOST=postgres
      - DB_PORT=5432
      - DB_USER=postgres
      - DB_PASSWORD=postgres
      - DB_NAME=demo
      - TENANT_ID=acme
    depends_on:
      postgres:
        condition: service_healthy

  postgres:
    image: postgres:15
    ports:
      - "5432:5432"
    environment:
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=postgres
      - POSTGRES_DB=demo
    volumes:
      - ./init.sql:/docker-entrypoint-initdb.d/init.sql
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 5s
      retries: 5

volumes:
  postgres_data:
```

#### init.sql (docker-compose用)

```sql
-- テナント: acme
CREATE SCHEMA acme;
CREATE TABLE acme.items (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE acme.health_check (
    id INTEGER PRIMARY KEY DEFAULT 1,
    status VARCHAR(10) DEFAULT 'ok'
);
INSERT INTO acme.health_check VALUES (1, 'ok');

-- 初期データ
INSERT INTO acme.items (name) VALUES ('Sample Item 1'), ('Sample Item 2');
```

---

### 2. terraform/shared/tenants.tfvars

```hcl
# 初期は1テナントで開始
# 検証で2, 3と増やしていく

tenants = {
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

  # テナント追加時にここに追記
  # "globex" = {
  #   display_name          = "Globex Inc"
  #   path_pattern          = "/globex/*"
  #   health_path           = "/globex/health"
  #   priority              = 200
  #   desired_count         = 1
  #   cpu                   = 256
  #   memory                = 512
  #   error_log_threshold   = 10
  #   latency_p99_threshold = 500
  #   error_rate_threshold  = 5
  #   slack_channel         = "alerts-globex"
  # }
}
```

---

### 3. terraform/aws/ - AWS インフラ

#### 重要ポイント

1. **NAT Gateway なし**: コスト節約のため、Fargate は Public Subnet に配置
2. **ACM**: HTTPS 用証明書は手動で作成し、ARN を変数で渡す
3. **for_each**: テナント関連リソースは全て `for_each = var.tenants` でループ

#### backend.tf のテンプレート

```hcl
terraform {
  backend "s3" {
    bucket         = "YOUR_BUCKET_NAME"  # 要変更
    key            = "datadog-ecs-demo/aws/terraform.tfstate"
    region         = "ap-northeast-1"
    encrypt        = true
    # dynamodb_table = "terraform-state-lock"  # オプション
  }
}
```

#### variables.tf で必要な変数

```hcl
variable "environment" {
  type    = string
  default = "dev"
}

variable "tenants" {
  type = map(object({
    display_name          = string
    path_pattern          = string
    health_path           = string
    priority              = number
    desired_count         = number
    cpu                   = number
    memory                = number
    error_log_threshold   = number
    latency_p99_threshold = number
    error_rate_threshold  = number
    slack_channel         = string
  }))
}

variable "acm_certificate_arn" {
  type        = string
  description = "ACM 証明書 ARN (HTTPS用)"
  default     = ""  # HTTP のみの場合は空
}

variable "dd_api_key" {
  type        = string
  sensitive   = true
  description = "Datadog API Key"
}
```

#### outputs.tf で出力する値

```hcl
output "rds_identifier" {
  value = module.database.identifier
}

output "rds_endpoint" {
  value = module.database.endpoint
}

output "ecs_cluster_name" {
  value = module.compute.cluster_name
}

output "alb_dns_name" {
  value = module.loadbalancer.dns_name
}

output "tenant_target_groups" {
  value = module.loadbalancer.target_groups
}

output "ecr_repository_url" {
  value = module.ecr.repository_url
}
```

---

### 4. terraform/datadog/ - Datadog 監視

#### data.tf

```hcl
data "terraform_remote_state" "aws" {
  backend = "s3"
  
  config = {
    bucket = "YOUR_BUCKET_NAME"  # aws側と同じ
    key    = "datadog-ecs-demo/aws/terraform.tfstate"
    region = "ap-northeast-1"
  }
}

locals {
  aws = data.terraform_remote_state.aws.outputs
}
```

#### monitoring/main.tf

```hcl
module "level0" {
  source = "./modules/level0-infra"

  rds_identifier   = var.rds_identifier
  ecs_cluster_name = var.ecs_cluster_name

  notification_targets = {
    critical = "@slack-alerts-critical"
    warning  = "@slack-alerts-warning"
  }
}

module "level2" {
  source = "./modules/level2-health"

  tenants = var.tenants
  alb_dns = var.alb_dns
}

module "level3" {
  source   = "./modules/level3-tenant"
  for_each = var.tenants

  tenant_id    = each.key
  config       = each.value
  service_name = "demo-api"
}

module "composite" {
  source   = "./modules/composite"
  for_each = var.tenants

  tenant_id          = each.key
  level0_monitor_ids = module.level0.all_critical_ids
  level2_monitor_id  = module.level2.monitor_ids[each.key]
  level3_monitor_ids = module.level3[each.key].all_ids
  slack_channel      = each.value.slack_channel
}
```

---

### 5. scripts/

#### setup-backend.sh

```bash
#!/bin/bash
set -e

BUCKET_NAME=${1:-"your-tfstate-bucket"}
REGION="ap-northeast-1"

echo "Creating S3 bucket: ${BUCKET_NAME}"
aws s3 mb s3://${BUCKET_NAME} --region ${REGION}

echo "Enabling versioning..."
aws s3api put-bucket-versioning \
  --bucket ${BUCKET_NAME} \
  --versioning-configuration Status=Enabled

echo "Enabling encryption..."
aws s3api put-bucket-encryption \
  --bucket ${BUCKET_NAME} \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

echo "Done! Update backend.tf with bucket name: ${BUCKET_NAME}"
```

#### deploy-aws.sh

```bash
#!/bin/bash
set -e

cd "$(dirname "$0")/../terraform/aws"

terraform init
terraform plan -var-file=../shared/tenants.tfvars -var="dd_api_key=${DD_API_KEY}"
terraform apply -var-file=../shared/tenants.tfvars -var="dd_api_key=${DD_API_KEY}" -auto-approve
```

#### deploy-datadog.sh

```bash
#!/bin/bash
set -e

cd "$(dirname "$0")/../terraform/datadog"

terraform init
terraform plan -var-file=../shared/tenants.tfvars
terraform apply -var-file=../shared/tenants.tfvars -auto-approve
```

---

## 実装順序

1. **app/** を完成させる
   - main.py, database.py, Dockerfile, docker-compose.yml
   - `docker-compose up` でローカル動作確認

2. **terraform/aws/network/** を実装
   - VPC, Subnet (Public のみ), Security Groups

3. **terraform/aws/database/** を実装
   - RDS PostgreSQL, Secrets Manager

4. **terraform/aws/ecr/** を実装
   - ECR Repository

5. **terraform/aws/compute/** を実装
   - ECS Cluster, Task Definition, Service

6. **terraform/aws/loadbalancer/** を実装
   - ALB, Target Groups, Listener Rules

7. **terraform/aws/datadog/** を実装
   - IAM Role for Integration, Secrets for DD_API_KEY

8. **terraform/aws/main.tf** でモジュール結合

9. **terraform/datadog/** を実装
   - integration.tf
   - monitoring/modules/* (level0, level2, level3, composite)
   - monitoring/main.tf

10. **scripts/** を実装

---

## 注意事項

1. **ACM 証明書**: HTTPS を使う場合、事前に ACM で証明書を作成し ARN を渡す
   - 検証段階では HTTP (80) のみでも可

2. **Datadog API Key**: 環境変数 `DD_API_KEY` と `DD_APP_KEY` を設定

3. **Synthetics ロケーション**: `aws:ap-northeast-1` を使用

4. **タグ付け**: 全リソースに以下のタグを付与
   - `Project = "datadog-ecs-demo"`
   - `Environment = var.environment`
   - `ManagedBy = "terraform"`
   - `Tenant = each.key` (テナント別リソース)

5. **State 分離**: AWS と Datadog で別 State ファイルを使用

6. **Composite Monitor の query 構文**:
   ```
   !monitor_id  → NOT (そのモニターがOK)
   &&           → AND
   ||           → OR
   ```
