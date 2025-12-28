"""
items テーブル SQLAlchemy Model

目的: サンプルデータの永続化、テナント別データ分離、RDS監視データ生成
影響範囲: items_repository.py（CRUD操作）、items_service.py（ビジネスロジック）
前提条件: PostgreSQL RDSが利用可能、tenant_idは有効なテナントID
"""

from sqlalchemy import Column, Integer, String, Text, DateTime, Index
from sqlalchemy.ext.declarative import declarative_base
from datetime import datetime

Base = declarative_base()


class Item(Base):
    """
    items テーブルのエンティティ定義

    責務:
        - サンプルデータの永続化
        - テナント別データ分離（マルチテナント対応）
        - RDS監視データ生成（FR-001: テナント別メトリクス収集）

    影響範囲:
        - items_repository.py: CRUD操作で使用
        - items_service.py: ビジネスロジックで使用
        - items_controller.py: APIレスポンスで使用

    前提条件:
        - PostgreSQL RDS が利用可能
        - tenant_id は有効なテナントID（tenant-a, tenant-b, tenant-c）
    """

    __tablename__ = 'items'

    # プライマリキー
    id = Column(Integer, primary_key=True, autoincrement=True, comment='サンプルデータID')

    # テナント分離
    tenant_id = Column(String(50), nullable=False, index=True, comment='テナントID')

    # データフィールド
    name = Column(String(100), nullable=False, comment='サンプルデータ名')
    description = Column(Text, nullable=True, comment='サンプルデータ説明')

    # タイムスタンプ（UTC）
    created_at = Column(
        DateTime,
        nullable=False,
        default=datetime.utcnow,
        comment='作成日時（UTC）'
    )
    updated_at = Column(
        DateTime,
        nullable=False,
        default=datetime.utcnow,
        onupdate=datetime.utcnow,
        comment='更新日時（UTC）'
    )

    # 複合インデックス: テナント別クエリ最適化
    __table_args__ = (
        Index('idx_tenant_id_created_at', 'tenant_id', 'created_at'),
    )

    def __repr__(self) -> str:
        """
        オブジェクトの文字列表現を返す（デバッグ用）

        Returns:
            str: "<Item(id=1, tenant_id='tenant-a', name='Sample Item 1')>"
        """
        return f"<Item(id={self.id}, tenant_id='{self.tenant_id}', name='{self.name}')>"

    def to_dict(self) -> dict:
        """
        エンティティを辞書形式に変換（API レスポンス用）

        目的: FastAPI JSONレスポンスに変換
        影響範囲: items_controller.py（APIレスポンス）

        Returns:
            dict: {
                "id": int,
                "tenant_id": str,
                "name": str,
                "description": str | None,
                "created_at": str (ISO 8601形式),
                "updated_at": str (ISO 8601形式)
            }
        """
        return {
            "id": self.id,
            "tenant_id": self.tenant_id,
            "name": self.name,
            "description": self.description,
            "created_at": self.created_at.isoformat() + "Z" if self.created_at else None,
            "updated_at": self.updated_at.isoformat() + "Z" if self.updated_at else None,
        }
