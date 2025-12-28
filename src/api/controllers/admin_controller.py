"""
管理機能コントローラー

目的: ECSタスク停止テスト、シャットダウンエンドポイント
影響範囲: 管理エンドポイント
前提条件: FastAPI、ddtrace
"""

from fastapi import APIRouter
import os
import signal
from ddtrace import tracer
from infrastructure.logger import get_logger

logger = get_logger()
router = APIRouter()


@router.post("/admin/shutdown")
def shutdown():
    """
    ECSタスク停止（グレースフルシャットダウン）

    目的:
        - ECSタスク停止テスト
        - Datadog監視（ECSタスク停止イベント）確認

    Returns:
        dict: シャットダウンメッセージ
            - message: str
            - status: str

    注意:
        - 本番環境では使用禁止（テスト環境のみ）
        - ECSタスクは自動的に再起動される
    """
    # Datadog カスタムタグ設定
    span = tracer.current_span()
    if span:
        span.set_tag("operation", "shutdown")

    # ログ出力
    logger.warning(
        "Shutdown request received",
        extra={
            "operation": "shutdown",
            "severity": "warning"
        }
    )

    # グレースフルシャットダウン（SIGTERM送信）
    os.kill(os.getpid(), signal.SIGTERM)

    return {
        "message": "Shutdown initiated",
        "status": "shutting_down"
    }
