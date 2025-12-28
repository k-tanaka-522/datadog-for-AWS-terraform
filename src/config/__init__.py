"""
設定管理パッケージ

環境変数から設定を読み込み、アプリケーション全体で使用可能にします。
"""

from .settings import settings

__all__ = ["settings"]
