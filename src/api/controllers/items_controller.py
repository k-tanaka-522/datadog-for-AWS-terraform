"""
サンプルデータCRUDコントローラー

目的: サンプルデータCRUD操作、RDS監視データ生成
影響範囲: APIエンドポイント（/{tenant_id}/items）
前提条件: ItemsService、TenantService
"""

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel, Field
from typing import List, Optional
from ddtrace import tracer

from repositories.database import get_db
from services.tenant_service import TenantService
from services.items_service import ItemsService
from infrastructure.logger import get_logger

logger = get_logger()
router = APIRouter()


class ItemCreateRequest(BaseModel):
    """サンプルデータ作成リクエスト"""
    name: str = Field(..., min_length=1, max_length=100, description="サンプルデータ名")
    description: Optional[str] = Field(None, description="サンプルデータ説明")


class ItemResponse(BaseModel):
    """サンプルデータレスポンス"""
    id: int
    tenant_id: str
    name: str
    description: Optional[str]
    created_at: str
    updated_at: str


@router.get("/{tenant_id}/items", response_model=List[ItemResponse])
def get_items(tenant_id: str, db: Session = Depends(get_db)):
    """
    サンプルデータ一覧取得

    目的:
        - テナント別サンプルデータ一覧取得
        - RDS監視データ生成

    Args:
        tenant_id (str): テナントID
        db (Session): データベースセッション

    Returns:
        List[ItemResponse]: サンプルデータリスト（作成日時降順）

    Raises:
        HTTPException(400): 無効なテナントID
    """
    # テナントID検証
    TenantService.validate_tenant(tenant_id)

    # Datadog カスタムタグ設定
    span = tracer.current_span()
    if span:
        span.set_tag("tenant.id", tenant_id)
        span.set_tag("operation", "get_items")

    # サンプルデータ一覧取得
    items_service = ItemsService(db)
    items = items_service.get_items(tenant_id)

    # ログ出力
    logger.info(
        f"Retrieved {len(items)} items for tenant {tenant_id}",
        extra={
            "tenant_id": tenant_id,
            "item_count": len(items)
        }
    )

    return [item.to_dict() for item in items]


@router.post("/{tenant_id}/items", response_model=ItemResponse, status_code=201)
def create_item(
    tenant_id: str,
    request: ItemCreateRequest,
    db: Session = Depends(get_db)
):
    """
    サンプルデータ作成

    目的:
        - サンプルデータ作成
        - RDS監視データ生成

    Args:
        tenant_id (str): テナントID
        request (ItemCreateRequest): 作成リクエスト
        db (Session): データベースセッション

    Returns:
        ItemResponse: 作成されたサンプルデータ

    Raises:
        HTTPException(400): 無効なテナントID、バリデーションエラー
    """
    # テナントID検証
    TenantService.validate_tenant(tenant_id)

    # Datadog カスタムタグ設定
    span = tracer.current_span()
    if span:
        span.set_tag("tenant.id", tenant_id)
        span.set_tag("operation", "create_item")

    # サンプルデータ作成
    items_service = ItemsService(db)
    item = items_service.create_item(
        tenant_id=tenant_id,
        name=request.name,
        description=request.description
    )

    # ログ出力
    logger.info(
        f"Created item {item.id} for tenant {tenant_id}",
        extra={
            "tenant_id": tenant_id,
            "item_id": item.id,
            "item_name": item.name
        }
    )

    return item.to_dict()


@router.get("/{tenant_id}/items/{item_id}", response_model=ItemResponse)
def get_item(tenant_id: str, item_id: int, db: Session = Depends(get_db)):
    """
    サンプルデータ詳細取得

    目的:
        - サンプルデータ詳細取得
        - テナント分離確認

    Args:
        tenant_id (str): テナントID
        item_id (int): サンプルデータID
        db (Session): データベースセッション

    Returns:
        ItemResponse: サンプルデータ詳細

    Raises:
        HTTPException(400): 無効なテナントID
        HTTPException(404): サンプルデータ未存在
    """
    # テナントID検証
    TenantService.validate_tenant(tenant_id)

    # Datadog カスタムタグ設定
    span = tracer.current_span()
    if span:
        span.set_tag("tenant.id", tenant_id)
        span.set_tag("operation", "get_item")
        span.set_tag("item.id", item_id)

    # サンプルデータ取得
    items_service = ItemsService(db)
    item = items_service.get_item_by_id(tenant_id, item_id)

    # ログ出力
    logger.info(
        f"Retrieved item {item_id} for tenant {tenant_id}",
        extra={
            "tenant_id": tenant_id,
            "item_id": item_id
        }
    )

    return item.to_dict()
