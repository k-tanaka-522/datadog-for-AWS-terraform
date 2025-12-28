# items_service.py - サンプルデータビジネスロジック 詳細設計

## 📋 ドキュメント情報

| 項目 | 内容 |
|------|------|
| ドキュメント名 | items_service.py - サンプルデータビジネスロジック 詳細設計 |
| バージョン | 1.1 |
| 作成日 | 2025-12-28 |
| 作成者 | App-Architect |

---

## 🎯 モジュール概要

### 責務
サンプルデータのビジネスロジック（CRUD処理の調整）

### 主要機能
1. **データ一覧取得**: テナント別データ一覧取得
2. **データ詳細取得**: ID別データ取得
3. **データ作成**: サンプルデータ作成（バリデーション含む）

### 依存関係
- **使用技術**: Python 3.10+
- **依存先**: `items_repository.py`
- **依存元**: `items_controller.py`

---

## 📊 クラス設計

### クラス名: ItemsService

**責務**: サンプルデータのビジネスロジック

---

## 🔧 メソッド詳細設計

### メソッド一覧

| メソッド | 説明 | 戻り値 |
|---------|------|--------|
| `__init__(repository: ItemsRepository)` | コンストラクタ | None |
| `get_items(tenant_id: str)` | データ一覧取得 | list[dict] |
| `get_item(tenant_id: str, item_id: int)` | データ詳細取得 | dict \| None |
| `create_item(tenant_id: str, name: str, description: Optional[str])` | データ作成 | dict |

---

## 📐 メソッド詳細

### 1. `__init__(repository: ItemsRepository)`

**目的**: コンストラクタ（Repository注入）

**関数シグネチャ**:
```python
from repositories.items_repository import ItemsRepository

class ItemsService:
    """
    サンプルデータのビジネスロジックを担当するサービス

    責務:
        - データ一覧取得
        - データ詳細取得
        - データ作成（バリデーション含む）

    影響範囲:
        - items_controller.py から呼び出される

    前提条件:
        - ItemsRepository が正しく初期化されている
    """

    def __init__(self, repository: ItemsRepository):
        """
        コンストラクタ

        Args:
            repository (ItemsRepository): items テーブルへのCRUD操作を行うリポジトリ
        """
        self.repository = repository
```

---

### 2. `get_items(tenant_id: str)`

**目的**: テナント別データ一覧取得

**関数シグネチャ**:
```python
def get_items(self, tenant_id: str) -> list[dict]:
    """
    テナント別にサンプルデータ一覧を取得

    Args:
        tenant_id (str): テナントID

    Returns:
        list[dict]: サンプルデータ一覧（辞書形式）

    例:
        >>> service = ItemsService(repository)
        >>> service.get_items("tenant-a")
        [
            {
                "id": 1,
                "tenant_id": "tenant-a",
                "name": "Sample Item 1",
                "description": "Description",
                "created_at": "2025-12-28T10:00:00Z",
                "updated_at": "2025-12-28T10:00:00Z"
            },
            ...
        ]
    """
    items = self.repository.find_by_tenant(tenant_id)
    return [item.to_dict() for item in items]
```

**処理フロー**:
```python
1. repository.find_by_tenant(tenant_id) でエンティティリストを取得
2. 各エンティティを to_dict() で辞書形式に変換
3. list[dict] を返却
```

**Datadog 監視**:
- **スパン名**: `items_service.get_items`
- **タグ**: `tenant_id=tenant-a`, `item_count=2`

---

### 3. `get_item(tenant_id: str, item_id: int)`

**目的**: ID別データ詳細取得

**関数シグネチャ**:
```python
def get_item(self, tenant_id: str, item_id: int) -> dict | None:
    """
    ID別にサンプルデータ詳細を取得

    Args:
        tenant_id (str): テナントID
        item_id (int): サンプルデータID

    Returns:
        dict | None: サンプルデータ（辞書形式）、見つからない場合は None

    例:
        >>> service = ItemsService(repository)
        >>> service.get_item("tenant-a", 1)
        {
            "id": 1,
            "tenant_id": "tenant-a",
            "name": "Sample Item 1",
            ...
        }
    """
    item = self.repository.find_by_id(tenant_id, item_id)
    if not item:
        return None
    return item.to_dict()
```

**処理フロー**:
```python
1. repository.find_by_id(tenant_id, item_id) でエンティティを取得
2. エンティティが None の場合は None を返却
3. エンティティが存在する場合は to_dict() で辞書形式に変換
4. dict を返却
```

**エラーハンドリング（Controller層で実施）**:
```python
# Controller 層での使用例
item = items_service.get_item("tenant-a", 1)
if not item:
    raise HTTPException(status_code=404, detail="Item not found")
```

---

### 4. `create_item(tenant_id: str, name: str, description: Optional[str])`

**目的**: サンプルデータ作成（バリデーション含む）

**関数シグネチャ**:
```python
from typing import Optional

def create_item(self, tenant_id: str, name: str, description: Optional[str] = None) -> dict:
    """
    サンプルデータを作成

    Args:
        tenant_id (str): テナントID
        name (str): サンプルデータ名（1〜100文字）
        description (Optional[str]): サンプルデータ説明（0〜500文字、任意）

    Returns:
        dict: 作成されたサンプルデータ（辞書形式）

    Raises:
        ValueError: バリデーションエラー時

    バリデーション:
        - name: 1〜100文字
        - description: 0〜500文字（任意）

    例:
        >>> service = ItemsService(repository)
        >>> service.create_item("tenant-a", "New Item", "Description")
        {
            "id": 3,
            "tenant_id": "tenant-a",
            "name": "New Item",
            ...
        }
    """
    # バリデーション
    if not name or len(name) < 1 or len(name) > 100:
        raise ValueError("name must be between 1 and 100 characters")

    if description and len(description) > 500:
        raise ValueError("description must be at most 500 characters")

    # データ作成
    item = self.repository.create(tenant_id, name, description)

    return item.to_dict()
```

**処理フロー**:
```python
1. name のバリデーション（1〜100文字）
2. description のバリデーション（0〜500文字）
3. バリデーションエラー時は ValueError を raise
4. repository.create() でエンティティ作成
5. to_dict() で辞書形式に変換
6. dict を返却
```

**バリデーションルール**:

| フィールド | 必須 | 最小長 | 最大長 | エラーメッセージ |
|----------|------|-------|-------|----------------|
| name | ✅ | 1 | 100 | "name must be between 1 and 100 characters" |
| description | ❌ | 0 | 500 | "description must be at most 500 characters" |

**エラーハンドリング（Controller層で実施）**:
```python
try:
    item = items_service.create_item("tenant-a", "New Item", "Description")
except ValueError as e:
    raise HTTPException(status_code=400, detail=str(e))
```

---

## 📝 改訂履歴

| 日付 | バージョン | 変更内容 | 作成者 |
|------|-----------|----------|--------|
| 2025-12-28 | 1.0 | 初版作成 | App-Architect |
| 2025-12-28 | 1.1 | Coderレビュー対応: description型ヒントをOptional[str]に修正 | App-Architect |
