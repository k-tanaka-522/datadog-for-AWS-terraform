"""
サンプルデータビジネスロジックサービス

目的: サンプルデータ操作、ビジネスルール適用
影響範囲: items_controller.py
前提条件: ItemsRepository が提供されている
"""

from sqlalchemy.orm import Session
from repositories.items_repository import ItemsRepository
from models.item import Item
from typing import List, Optional


class ItemNotFoundError(Exception):
    """
    サンプルデータ未存在エラー

    発生条件:
        - 指定されたIDのサンプルデータが存在しない
        - テナント分離により、他テナントのデータを取得しようとした
    """
    pass


class ItemsService:
    """
    サンプルデータビジネスロジックサービス

    責務:
        - サンプルデータのCRUD操作
        - ビジネスルールの適用
        - Repository層へのアクセス

    影響範囲:
        - items_controller.py（APIエンドポイント）

    前提条件:
        - ItemsRepository が提供されている
        - tenant_id は事前にバリデーション済み
    """

    def __init__(self, db: Session):
        """
        Service初期化

        Args:
            db (Session): SQLAlchemy セッション
        """
        self.repository = ItemsRepository(db)

    def get_items(self, tenant_id: str) -> List[Item]:
        """
        テナント別にサンプルデータ一覧を取得

        目的: 一覧取得API対応
        影響範囲: items_controller.py（GET /{tenant_id}/items）

        Args:
            tenant_id (str): テナントID

        Returns:
            List[Item]: サンプルデータリスト（作成日時降順）
        """
        return self.repository.find_by_tenant(tenant_id)

    def get_item_by_id(self, tenant_id: str, item_id: int) -> Item:
        """
        ID別にサンプルデータを取得

        目的: 詳細取得API対応
        影響範囲: items_controller.py（GET /{tenant_id}/items/{id}）

        Args:
            tenant_id (str): テナントID
            item_id (int): サンプルデータID

        Returns:
            Item: サンプルデータ

        Raises:
            ItemNotFoundError: データが存在しない場合
        """
        item = self.repository.find_by_id(tenant_id, item_id)
        if not item:
            raise ItemNotFoundError(
                f"Item {item_id} not found for tenant {tenant_id}"
            )
        return item

    def create_item(
        self,
        tenant_id: str,
        name: str,
        description: Optional[str] = None
    ) -> Item:
        """
        サンプルデータを作成

        目的: データ作成API対応
        影響範囲: items_controller.py（POST /{tenant_id}/items）

        Args:
            tenant_id (str): テナントID
            name (str): サンプルデータ名
            description (Optional[str]): サンプルデータ説明

        Returns:
            Item: 作成されたサンプルデータ

        ビジネスルール:
            - name は必須（1文字以上100文字以下）
            - description は任意
        """
        # ビジネスルール検証
        if not name or len(name.strip()) == 0:
            raise ValueError("Name cannot be empty")

        if len(name) > 100:
            raise ValueError("Name must be 100 characters or less")

        return self.repository.create(tenant_id, name, description)

    def delete_item(self, tenant_id: str, item_id: int) -> bool:
        """
        サンプルデータを削除

        目的: データ削除API対応（将来実装）
        影響範囲: items_controller.py（DELETE /{tenant_id}/items/{id}）

        Args:
            tenant_id (str): テナントID
            item_id (int): サンプルデータID

        Returns:
            bool: True（削除成功）、False（データ未存在）
        """
        return self.repository.delete(tenant_id, item_id)

    def count_items(self, tenant_id: str) -> int:
        """
        テナント別のデータ件数を取得（監視用）

        目的: Datadog監視メトリクス生成
        影響範囲: monitoring_service.py

        Args:
            tenant_id (str): テナントID

        Returns:
            int: データ件数
        """
        return self.repository.count_by_tenant(tenant_id)
