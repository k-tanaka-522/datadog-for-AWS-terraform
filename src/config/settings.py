"""
アプリケーション設定管理

目的: 環境変数から設定を一元管理し、アプリケーション全体で使用
影響範囲: 全モジュール（database.py, logger.py, tenant_service.py等）
前提条件: 環境変数が設定されていること（.envまたはECSタスク定義）
"""

import os
from typing import List


class Settings:
    """
    アプリケーション設定クラス

    責務:
        - 環境変数から設定を読み込み
        - デフォルト値の提供
        - 設定の型安全な取得

    影響範囲:
        - database.py: DATABASE_URL
        - logger.py: LOG_LEVEL
        - tenant_service.py: VALID_TENANTS
        - datadog_middleware.py: DD_SERVICE, DD_ENV, DD_VERSION

    前提条件:
        - DATABASE_URL または DB_HOST/DB_PORT/DB_USER/DB_PASSWORD/DB_NAME
        - VALID_TENANTS: カンマ区切りのテナントID
    """

    # Database設定（SSL/TLS必須）
    # ECS環境では個別のDB_*変数から構築、ローカルではDATABASE_URLを使用
    @staticmethod
    def _build_database_url() -> str:
        # 直接指定があればそれを使用
        if os.getenv("DATABASE_URL"):
            return os.getenv("DATABASE_URL")

        # 個別の環境変数から構築
        db_host = os.getenv("DB_HOST", "localhost")
        db_port = os.getenv("DB_PORT", "5432")
        db_user = os.getenv("DB_USER", "demo_user")
        db_password = os.getenv("DB_PASSWORD", "demo_password")
        db_name = os.getenv("DB_NAME", "demo_db")

        return f"postgresql://{db_user}:{db_password}@{db_host}:{db_port}/{db_name}?sslmode=require"

    DATABASE_URL: str = _build_database_url()

    # Datadog設定
    DD_SERVICE: str = os.getenv("DD_SERVICE", "demo-api")
    DD_ENV: str = os.getenv("DD_ENV", "poc")
    DD_VERSION: str = os.getenv("DD_VERSION", "1.0.0")
    DD_AGENT_HOST: str = os.getenv("DD_AGENT_HOST", "datadog-agent")

    # アプリケーション設定
    VALID_TENANTS: str = os.getenv("VALID_TENANTS", "tenant-a,tenant-b,tenant-c")
    LOG_LEVEL: str = os.getenv("LOG_LEVEL", "INFO")

    @property
    def valid_tenant_list(self) -> List[str]:
        """
        有効なテナントIDをリストで取得

        Returns:
            List[str]: テナントIDリスト（例: ["tenant-a", "tenant-b", "tenant-c"]）
        """
        return [tenant.strip() for tenant in self.VALID_TENANTS.split(",")]


# シングルトンインスタンス
settings = Settings()
