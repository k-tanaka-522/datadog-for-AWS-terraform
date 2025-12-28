"""
エラーハンドリングミドルウェア

目的: 例外の一元キャッチ、エラーログ出力、適切なHTTPステータス返却
影響範囲: すべてのエンドポイント
前提条件: logger.py（構造化ログ）、ddtrace（Datadog APM）
"""

from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import JSONResponse
from datetime import datetime
from ddtrace import tracer
from infrastructure.logger import get_logger
from services.tenant_service import InvalidTenantError
from services.items_service import ItemNotFoundError

logger = get_logger()


def register_error_handlers(app: FastAPI) -> None:
    """
    FastAPIアプリケーションにエラーハンドラを登録

    目的:
        - 例外の一元キャッチ
        - エラーログ出力（構造化ログ、JSON形式）
        - 適切なHTTPステータスコードとエラーメッセージを返却

    影響範囲:
        - すべてのエンドポイント

    前提条件:
        - logger.py で構造化ログが設定されている
        - ddtrace が初期化されている

    Args:
        app (FastAPI): FastAPIアプリケーションインスタンス
    """

    @app.exception_handler(InvalidTenantError)
    async def invalid_tenant_error_handler(request: Request, exc: InvalidTenantError):
        """
        無効なテナントIDエラーハンドラ

        ステータスコード: 400 Bad Request
        """
        logger.error(
            f"Invalid tenant error: {exc}",
            extra={
                "error_type": "invalid_tenant",
                "severity": "error",
                "path": str(request.url)
            }
        )

        # Datadog APM にエラートレースを送信
        span = tracer.current_span()
        if span:
            span.set_tag("error", True)
            span.set_tag("error.type", "invalid_tenant")
            span.set_tag("error.message", str(exc))

        return JSONResponse(
            status_code=400,
            content={
                "status": "error",
                "error_type": "invalid_tenant",
                "message": str(exc),
                "timestamp": datetime.utcnow().isoformat() + "Z"
            }
        )

    @app.exception_handler(ItemNotFoundError)
    async def item_not_found_error_handler(request: Request, exc: ItemNotFoundError):
        """
        サンプルデータ未存在エラーハンドラ

        ステータスコード: 404 Not Found
        """
        logger.warning(
            f"Item not found: {exc}",
            extra={
                "error_type": "item_not_found",
                "severity": "warning",
                "path": str(request.url)
            }
        )

        # Datadog APM にエラートレースを送信
        span = tracer.current_span()
        if span:
            span.set_tag("error", True)
            span.set_tag("error.type", "item_not_found")
            span.set_tag("error.message", str(exc))

        return JSONResponse(
            status_code=404,
            content={
                "status": "error",
                "error_type": "item_not_found",
                "message": str(exc),
                "timestamp": datetime.utcnow().isoformat() + "Z"
            }
        )

    @app.exception_handler(ValueError)
    async def value_error_handler(request: Request, exc: ValueError):
        """
        バリデーションエラーハンドラ

        ステータスコード: 400 Bad Request
        """
        logger.warning(
            f"Validation error: {exc}",
            extra={
                "error_type": "validation_error",
                "severity": "warning",
                "path": str(request.url)
            }
        )

        return JSONResponse(
            status_code=400,
            content={
                "status": "error",
                "error_type": "validation_error",
                "message": str(exc),
                "timestamp": datetime.utcnow().isoformat() + "Z"
            }
        )

    @app.exception_handler(HTTPException)
    async def http_exception_handler(request: Request, exc: HTTPException):
        """
        HTTPExceptionハンドラ（FastAPI標準例外）

        ステータスコード: 例外で指定されたステータスコード
        """
        logger.error(
            f"HTTP exception: {exc.detail}",
            extra={
                "error_type": "http_exception",
                "severity": "error",
                "status_code": exc.status_code,
                "path": str(request.url)
            }
        )

        # Datadog APM にエラートレースを送信
        span = tracer.current_span()
        if span:
            span.set_tag("error", True)
            span.set_tag("error.type", "http_exception")
            span.set_tag("error.message", exc.detail)
            span.set_tag("http.status_code", exc.status_code)

        return JSONResponse(
            status_code=exc.status_code,
            content={
                "status": "error",
                "error_type": "http_exception",
                "message": exc.detail,
                "timestamp": datetime.utcnow().isoformat() + "Z"
            }
        )

    @app.exception_handler(Exception)
    async def general_exception_handler(request: Request, exc: Exception):
        """
        一般例外ハンドラ（予期しない例外）

        ステータスコード: 500 Internal Server Error
        """
        logger.error(
            f"Unexpected error: {exc}",
            exc_info=True,
            extra={
                "error_type": "unexpected_error",
                "severity": "error",
                "path": str(request.url)
            }
        )

        # Datadog APM にエラートレースを送信
        span = tracer.current_span()
        if span:
            span.set_tag("error", True)
            span.set_tag("error.type", "unexpected_error")
            span.set_tag("error.message", str(exc))

        return JSONResponse(
            status_code=500,
            content={
                "status": "error",
                "error_type": "unexpected_error",
                "message": "An unexpected error occurred",
                "timestamp": datetime.utcnow().isoformat() + "Z"
            }
        )
