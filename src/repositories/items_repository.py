"""
items テーブル CRUD Repository

目的: itemsテーブルへのデータアクセス、SQLインジェクション対策、テナント分離
影響範囲: items_service.py（ビジネスロジック）
前提条件: database.pyでセッションが提供されている
"""

from sqlalchemy.orm import Session
from sqlalchemy import text
from models.item import Item
from typing import List, Optional


class ItemsRepository:
    """
    items テーブルのCRUD操作を提供

    責務:
        - items テーブルへのCRUD操作
        - テナント分離（すべてのクエリにtenant_idフィルタ）
        - SQLインジェクション対策（パラメータ化クエリ使用）

    影響範囲:
        - items_service.py: ビジネスロジックで使用

    前提条件:
        - database.py でセッションが提供されている
        - tenant_id は事前にバリデーション済み
    """

    def __init__(self, db: Session):
        """
        Repository初期化

        Args:
            db (Session): SQLAlchemy セッション
        """
        self.db = db

    def find_by_tenant(self, tenant_id: str) -> List[Item]:
        """
        テナント別にサンプルデータ一覧を取得

        目的: テナント別データ分離、一覧取得API対応
        影響範囲: items_service.py（get_items）

        Args:
            tenant_id (str): テナントID

        Returns:
            List[Item]: サンプルデータリスト（作成日時降順）

        セキュリティ:
            - SQLインジェクション対策: ORMの自動パラメータ化
            - テナント分離: WHERE tenant_id = :tenant_id
        """
        return self.db.query(Item).filter(
            Item.tenant_id == tenant_id
        ).order_by(
            Item.created_at.desc()
        ).all()

    def find_by_id(self, tenant_id: str, item_id: int) -> Optional[Item]:
        """
        ID別にサンプルデータを取得（テナント分離）

        目的: 詳細取得API対応、テナント分離
        影響範囲: items_service.py（get_item_by_id）

        Args:
            tenant_id (str): テナントID
            item_id (int): サンプルデータID

        Returns:
            Optional[Item]: サンプルデータ（未存在の場合 None）

        セキュリティ:
            - テナント分離: 他テナントのデータは取得不可
        """
        return self.db.query(Item).filter(
            Item.tenant_id == tenant_id,
            Item.id == item_id
        ).first()

    def create(self, tenant_id: str, name: str, description: Optional[str] = None) -> Item:
        """
        サンプルデータを作成

        目的: データ作成API対応、RDS監視データ生成
        影響範囲: items_service.py（create_item）

        Args:
            tenant_id (str): テナントID
            name (str): サンプルデータ名
            description (Optional[str]): サンプルデータ説明

        Returns:
            Item: 作成されたサンプルデータ

        例外:
            IntegrityError: 制約違反時（Repository層では発生させず、Service層でキャッチ）

        セキュリティ:
            - SQLインジェクション対策: ORMの自動パラメータ化
            - テナント分離: tenant_idを必須設定
        """
        item = Item(
            tenant_id=tenant_id,
            name=name,
            description=description
        )
        self.db.add(item)
        self.db.commit()
        self.db.refresh(item)
        return item

    def delete(self, tenant_id: str, item_id: int) -> bool:
        """
        サンプルデータを削除（テナント分離）

        目的: データ削除API対応（将来実装）
        影響範囲: items_service.py（delete_item）

        Args:
            tenant_id (str): テナントID
            item_id (int): サンプルデータID

        Returns:
            bool: True（削除成功）、False（データ未存在）

        セキュリティ:
            - テナント分離: 他テナントのデータは削除不可
        """
        item = self.find_by_id(tenant_id, item_id)
        if not item:
            return False

        self.db.delete(item)
        self.db.commit()
        return True

    def count_by_tenant(self, tenant_id: str) -> int:
        """
        テナント別のデータ件数を取得（監視用）

        目的: Datadog監視メトリクス生成
        影響範囲: monitoring_service.py

        Args:
            tenant_id (str): テナントID

        Returns:
            int: データ件数
        """
        return self.db.query(Item).filter(
            Item.tenant_id == tenant_id
        ).count()
