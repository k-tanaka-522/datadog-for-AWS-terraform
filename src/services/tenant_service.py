"""
テナント検証サービス

目的: テナントID検証、テナント分離の実現、不正アクセス防止
影響範囲: 全Controller（すべてのエンドポイントで使用）
前提条件: VALID_TENANTS環境変数が設定されている
"""

from config.settings import settings
from typing import List


class InvalidTenantError(Exception):
    """
    無効なテナントIDエラー

    発生条件:
        - tenant_id が VALID_TENANTS に含まれていない
        - tenant_id が空文字列
    """
    pass


class TenantService:
    """
    テナント検証サービス

    責務:
        - テナントIDの有効性検証
        - 許可リストベースのアクセス制御
        - テナント分離の実現

    影響範囲:
        - 全Controller（すべてのエンドポイントで使用）

    前提条件:
        - VALID_TENANTS 環境変数が設定されていること
    """

    @staticmethod
    def get_valid_tenants() -> List[str]:
        """
        有効なテナントIDリストを取得

        Returns:
            List[str]: 有効なテナントIDリスト（例: ["tenant-a", "tenant-b", "tenant-c"]）
        """
        return settings.valid_tenant_list

    @staticmethod
    def validate_tenant(tenant_id: str) -> None:
        """
        テナントIDの有効性を検証

        目的:
            - テナント分離を実現
            - 不正なテナントアクセスを防止

        影響範囲:
            - すべてのエンドポイント（/{tenant_id}/で始まるパス）

        前提条件:
            - VALID_TENANTS 環境変数が設定されていること

        Args:
            tenant_id (str): テナントID

        Raises:
            InvalidTenantError: 無効なテナントIDの場合

        セキュリティ:
            - 許可リストベース（ホワイトリスト方式）
            - 環境変数で柔軟に設定可能
        """
        if not tenant_id or tenant_id.strip() == "":
            raise InvalidTenantError("Tenant ID cannot be empty")

        valid_tenants = TenantService.get_valid_tenants()

        if tenant_id not in valid_tenants:
            raise InvalidTenantError(
                f"Invalid tenant ID: {tenant_id}. "
                f"Valid tenants: {', '.join(valid_tenants)}"
            )

    @staticmethod
    def is_valid_tenant(tenant_id: str) -> bool:
        """
        テナントIDの有効性を真偽値で返す（例外を投げない）

        Args:
            tenant_id (str): テナントID

        Returns:
            bool: True（有効）、False（無効）
        """
        try:
            TenantService.validate_tenant(tenant_id)
            return True
        except InvalidTenantError:
            return False
