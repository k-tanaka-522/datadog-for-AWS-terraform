#!/bin/bash
#
# Terraform Backend (S3) 初期セットアップ
#
set -e

BUCKET_NAME=${1:-""}
REGION="ap-northeast-1"

if [ -z "$BUCKET_NAME" ]; then
    echo "Usage: $0 <bucket-name>"
    echo "Example: $0 my-tfstate-bucket"
    exit 1
fi

echo "=========================================="
echo " Terraform Backend Setup"
echo "=========================================="
echo ""
echo "Bucket Name: ${BUCKET_NAME}"
echo "Region: ${REGION}"
echo ""

# S3 バケット作成
echo "[1/4] Creating S3 bucket..."
if aws s3 ls "s3://${BUCKET_NAME}" 2>&1 | grep -q 'NoSuchBucket'; then
    aws s3 mb s3://${BUCKET_NAME} --region ${REGION}
    echo "  ✓ Bucket created"
else
    echo "  ✓ Bucket already exists"
fi

# バージョニング有効化
echo "[2/4] Enabling versioning..."
aws s3api put-bucket-versioning \
    --bucket ${BUCKET_NAME} \
    --versioning-configuration Status=Enabled
echo "  ✓ Versioning enabled"

# 暗号化設定
echo "[3/4] Enabling encryption..."
aws s3api put-bucket-encryption \
    --bucket ${BUCKET_NAME} \
    --server-side-encryption-configuration '{
        "Rules": [{
            "ApplyServerSideEncryptionByDefault": {
                "SSEAlgorithm": "AES256"
            }
        }]
    }'
echo "  ✓ Encryption enabled"

# パブリックアクセスブロック
echo "[4/4] Blocking public access..."
aws s3api put-public-access-block \
    --bucket ${BUCKET_NAME} \
    --public-access-block-configuration '{
        "BlockPublicAcls": true,
        "IgnorePublicAcls": true,
        "BlockPublicPolicy": true,
        "RestrictPublicBuckets": true
    }'
echo "  ✓ Public access blocked"

# DynamoDB テーブル作成（State Lock用）
echo "[5/5] Creating DynamoDB table for state locking..."
DYNAMODB_TABLE="${BUCKET_NAME}-lock"

if aws dynamodb describe-table --table-name ${DYNAMODB_TABLE} --region ${REGION} 2>&1 | grep -q 'ResourceNotFoundException'; then
    aws dynamodb create-table \
        --table-name ${DYNAMODB_TABLE} \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region ${REGION}
    echo "  ✓ DynamoDB table created"
else
    echo "  ✓ DynamoDB table already exists"
fi

echo ""
echo "=========================================="
echo " Setup Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo ""
echo "1. Update infra/terraform/aws/backend.tf:"
echo ""
echo '   terraform {'
echo '     backend "s3" {'
echo "       bucket         = \"${BUCKET_NAME}\""
echo '       key            = "aws/terraform.tfstate"'
echo '       region         = "ap-northeast-1"'
echo '       encrypt        = true'
echo "       dynamodb_table = \"${DYNAMODB_TABLE}\""
echo '     }'
echo '   }'
echo ""
echo "2. Update infra/terraform/datadog/backend.tf with the same settings"
echo "   (change key to 'datadog/terraform.tfstate')"
echo ""
echo "3. Run: cd infra/terraform/aws && terraform init"
echo ""
