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

echo ""
echo "=========================================="
echo " Setup Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo ""
echo "1. Update terraform/aws/backend.tf:"
echo ""
echo '   terraform {'
echo '     backend "s3" {'
echo "       bucket = \"${BUCKET_NAME}\""
echo '       key    = "datadog-ecs-demo/aws/terraform.tfstate"'
echo '       region = "ap-northeast-1"'
echo '       encrypt = true'
echo '     }'
echo '   }'
echo ""
echo "2. Update terraform/datadog/backend.tf with the same bucket"
echo ""
echo "3. Run: cd terraform/aws && terraform init"
echo ""
