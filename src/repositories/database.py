"""
データベース接続管理

目的: PostgreSQL RDSへの接続管理とセッション提供
影響範囲: 全Repository、全Controller（FastAPI Dependency Injection）
前提条件: DATABASE_URLが正しく設定されている、PostgreSQL RDSが起動している
"""

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, Session
from typing import Generator
from config.settings import settings
from models.item import Base
from infrastructure.logger import get_logger

logger = get_logger()


# データベース接続URL（環境変数から取得、SSL/TLS必須）
DATABASE_URL = settings.DATABASE_URL

# エンジン作成（接続プール設定）
engine = create_engine(
    DATABASE_URL,
    pool_size=10,          # 常時維持する接続数（NFR-003: テナント数10〜100対応）
    max_overflow=20,       # 最大接続数超過時の追加接続数
    pool_pre_ping=True,    # 接続前にヘルスチェック（切断検知）
    echo=False,            # SQLログ出力（本番環境では False）
)

# セッションファクトリ
SessionLocal = sessionmaker(
    autocommit=False,
    autoflush=False,
    bind=engine
)


def get_db() -> Generator[Session, None, None]:
    """
    データベースセッションを取得する（FastAPI Dependency Injection 用）

    目的:
        - FastAPI エンドポイントにセッションを注入
        - リクエスト終了時に自動的にセッションをクローズ

    影響範囲:
        - すべての Controller（Depends(get_db) で使用）
        - すべての Repository（セッションを受け取る）

    前提条件:
        - DATABASE_URL が正しく設定されている
        - PostgreSQL RDS が起動している

    Yields:
        Session: SQLAlchemy セッション

    例外:
        OperationalError: DB接続失敗時

    使用例:
        @app.get("/items")
        def get_items(db: Session = Depends(get_db)):
            items = db.query(Item).all()
            return items
    """
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def init_db() -> None:
    """
    データベースを初期化する（テーブル作成）

    目的:
        - 開発環境でのテーブル自動作成
        - テスト環境でのDB初期化

    影響範囲:
        - items テーブルの作成

    前提条件:
        - PostgreSQL RDS が起動している
        - Base に全 Model が登録されている

    注意:
        - 本番環境では使用しない（Alembic によるマイグレーション推奨）

    使用例:
        @app.on_event("startup")
        async def startup_event():
            init_db()
    """
    Base.metadata.create_all(bind=engine)


def check_db_connection() -> bool:
    """
    データベース接続を確認する（ヘルスチェック用）

    目的:
        - ヘルスチェックエンドポイントで使用
        - DB接続障害の早期検知

    影響範囲:
        - health_controller.py（ヘルスチェック）

    Returns:
        bool: True（接続成功）、False（接続失敗）

    例外:
        なし（内部でキャッチして False を返す）
    """
    try:
        db = SessionLocal()
        db.execute("SELECT 1")
        db.close()
        return True
    except Exception as e:
        # エラーログ出力（構造化ログ）
        logger.error(
            f"DB connection check failed: {e}",
            exc_info=True,
            extra={
                "error_type": "db_connection_check_failed",
                "severity": "error"
            }
        )
        return False
