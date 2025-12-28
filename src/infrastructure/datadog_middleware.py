"""
Datadog APM統合ミドルウェア

目的: Datadog APMトレース送信、カスタムタグ設定
影響範囲: すべてのエンドポイント
前提条件: ddtrace がインストールされている、DD_SERVICE等の環境変数が設定されている
"""

from ddtrace import patch_all, tracer
from config.settings import settings
from infrastructure.logger import get_logger
import os

logger = get_logger()


def setup_datadog() -> None:
    """
    Datadog APMを初期化

    目的:
        - ddtrace の自動インストルメンテーション有効化
        - サービス名、環境、バージョンを設定
        - カスタムタグの設定

    影響範囲:
        - すべてのHTTPリクエスト
        - すべてのデータベースクエリ

    前提条件:
        - DD_SERVICE, DD_ENV, DD_VERSION 環境変数が設定されている
        - DD_AGENT_HOST 環境変数が設定されている（デフォルト: datadog-agent）

    環境変数:
        - DD_SERVICE: サービス名（例: demo-api）
        - DD_ENV: 環境名（例: poc, dev, prod）
        - DD_VERSION: バージョン（例: 1.0.0）
        - DD_AGENT_HOST: Datadog Agent のホスト名（ECS サイドカー: datadog-agent）
    """
    # 環境変数設定（ddtrace が自動的に読み取る）
    os.environ["DD_SERVICE"] = settings.DD_SERVICE
    os.environ["DD_ENV"] = settings.DD_ENV
    os.environ["DD_VERSION"] = settings.DD_VERSION

    # Datadog Agent ホスト設定
    os.environ["DD_AGENT_HOST"] = settings.DD_AGENT_HOST
    os.environ["DD_TRACE_AGENT_PORT"] = "8126"  # デフォルトポート

    # 自動インストルメンテーション有効化
    # FastAPI, SQLAlchemy, requests 等を自動的にトレース
    patch_all()

    # グローバルタグ設定
    tracer.set_tags({
        "service": settings.DD_SERVICE,
        "env": settings.DD_ENV,
        "version": settings.DD_VERSION,
    })

    logger.info(
        "Datadog APM initialized",
        extra={
            "dd_service": settings.DD_SERVICE,
            "dd_env": settings.DD_ENV,
            "dd_version": settings.DD_VERSION
        }
    )
