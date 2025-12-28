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
        - DATABASE_URL: PostgreSQL接続文字列（sslmode=require必須）
        - VALID_TENANTS: カンマ区切りのテナントID
    """

    # Database設定（SSL/TLS必須）
    DATABASE_URL: str = os.getenv(
        "DATABASE_URL",
        "postgresql://demo_user:demo_password@localhost:5432/demo_db?sslmode=require"
    )

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
