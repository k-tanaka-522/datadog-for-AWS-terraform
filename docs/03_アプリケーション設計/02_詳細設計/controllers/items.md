# items_controller.py - サンプルデータCRUD 詳細設計

## 📋 ドキュメント情報

| 項目 | 内容 |
|------|------|
| ドキュメント名 | items_controller.py - サンプルデータCRUD 詳細設計 |
| バージョン | 1.1 |
| 作成日 | 2025-12-28 |
| 作成者 | App-Architect |

---

## 🎯 モジュール概要

### 責務
- サンプルデータCRUD処理（FR-001 RDS監視）
- テナント別データ分離

### 依存関係
- **依存先**: `tenant_service.py`, `items_service.py`
- **依存元**: FastAPI Router

---

## 📐 エンドポイント設計

### 1. GET /{tenant_id}/items

**関数シグネチャ**:
```python
from fastapi import APIRouter, HTTPException, Depends
from sqlalchemy.orm import Session
from services.tenant_service import TenantService
from services.items_service import ItemsService
from repositories.items_repository import ItemsRepository
from database import get_db
from ddtrace import tracer

router = APIRouter()
tenant_service = TenantService()

@router.get("/{tenant_id}/items")
def get_items(tenant_id: str, db: Session = Depends(get_db)):
    """
    サンプルデータ一覧取得

    Args:
        tenant_id (str): テナントID
        db (Session): データベースセッション

    Returns:
        dict: サンプルデータ一覧

    Raises:
        HTTPException(400): 無効なテナント
    """
    # Datadog カスタムタグ設定
    span = tracer.current_span()
    if span:
        span.set_tag("tenant_id", tenant_id)

    # テナント検証
    if not tenant_service.validate_tenant(tenant_id):
        raise HTTPException(status_code=400, detail="Invalid tenant")

    # データ取得
    repository = ItemsRepository(db)
    service = ItemsService(repository)
    items = service.get_items(tenant_id)

    return {
        "items": items,
        "count": len(items)
    }
```

---

### 2. POST /{tenant_id}/items

**関数シグネチャ**:
```python
from pydantic import BaseModel
from typing import Optional

class ItemCreateRequest(BaseModel):
    name: str
    description: Optional[str] = None

@router.post("/{tenant_id}/items", status_code=201)
def create_item(tenant_id: str, request: ItemCreateRequest, db: Session = Depends(get_db)):
    """
    サンプルデータ作成

    Args:
        tenant_id (str): テナントID
        request (ItemCreateRequest): name, description
        db (Session): データベースセッション

    Returns:
        dict: 作成されたサンプルデータ

    Raises:
        HTTPException(400): 無効なテナント、バリデーションエラー
        HTTPException(500): DB接続失敗
    """
    # Datadog カスタムタグ設定
    span = tracer.current_span()
    if span:
        span.set_tag("tenant_id", tenant_id)

    # テナント検証
    if not tenant_service.validate_tenant(tenant_id):
        raise HTTPException(status_code=400, detail="Invalid tenant")

    # データ作成
    try:
        repository = ItemsRepository(db)
        service = ItemsService(repository)
        item = service.create_item(tenant_id, request.name, request.description)
        return item
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail="Failed to create item")
```

---

### 3. GET /{tenant_id}/items/{id}

**関数シグネチャ**:
```python
@router.get("/{tenant_id}/items/{id}")
def get_item(tenant_id: str, id: int, db: Session = Depends(get_db)):
    """
    サンプルデータ詳細取得

    Args:
        tenant_id (str): テナントID
        id (int): サンプルデータID
        db (Session): データベースセッション

    Returns:
        dict: サンプルデータ詳細

    Raises:
        HTTPException(400): 無効なテナント
        HTTPException(404): データ未存在
    """
    # Datadog カスタムタグ設定
    span = tracer.current_span()
    if span:
        span.set_tag("tenant_id", tenant_id)
        span.set_tag("item_id", id)

    # テナント検証
    if not tenant_service.validate_tenant(tenant_id):
        raise HTTPException(status_code=400, detail="Invalid tenant")

    # データ取得
    repository = ItemsRepository(db)
    service = ItemsService(repository)
    item = service.get_item(tenant_id, id)

    if not item:
        raise HTTPException(status_code=404, detail=f"Item with id {id} not found")

    return item
```

---

## 📝 改訂履歴

| 日付 | バージョン | 変更内容 | 作成者 |
|------|-----------|----------|--------|
| 2025-12-28 | 1.0 | 初版作成 | App-Architect |
| 2025-12-28 | 1.1 | Coderレビュー対応: description型ヒントをOptional[str]に統一 | App-Architect |
