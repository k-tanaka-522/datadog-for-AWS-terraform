"""
FastAPI アプリケーションエントリーポイント

目的: FastAPIアプリケーション初期化、ルーティング設定、Datadog APM統合
影響範囲: アプリケーション全体
前提条件: 全モジュールが実装されている
"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from infrastructure.datadog_middleware import setup_datadog
from infrastructure.error_handler import register_error_handlers
from infrastructure.logger import get_logger
from repositories.database import init_db

# Controllersインポート
from api.controllers import health_controller
from api.controllers import items_controller
from api.controllers import simulate_controller
from api.controllers import admin_controller

# Datadog APM初期化（アプリケーション起動前に実行）
setup_datadog()

# ロガー初期化
logger = get_logger()

# FastAPIアプリケーション初期化
app = FastAPI(
    title="demo-api",
    description="Datadog for AWS Terraform PoC - Demo API",
    version="1.0.0",
    docs_url="/docs",  # Swagger UI
    redoc_url="/redoc",  # ReDoc
)

# CORS設定（開発環境用）
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # 本番環境では制限する
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# エラーハンドラ登録
register_error_handlers(app)

# ルーター登録
app.include_router(health_controller.router, tags=["Health Check"])
app.include_router(items_controller.router, tags=["Items"])
app.include_router(simulate_controller.router, tags=["Simulate"])
app.include_router(admin_controller.router, tags=["Admin"])


@app.on_event("startup")
async def startup_event():
    """
    アプリケーション起動時処理

    目的:
        - データベース初期化（開発環境のみ）
        - 起動ログ出力

    影響範囲:
        - アプリケーション起動時
    """
    logger.info("Application starting up")

    # データベース初期化（テーブル作成）
    # 本番環境ではAlembicによるマイグレーション推奨
    try:
        init_db()
        logger.info("Database initialized successfully")
    except Exception as e:
        logger.error(
            f"Database initialization failed: {e}",
            exc_info=True,
            extra={
                "error_type": "startup_failure",
                "severity": "error"
            }
        )


@app.on_event("shutdown")
async def shutdown_event():
    """
    アプリケーション停止時処理

    目的:
        - 停止ログ出力
        - リソースクリーンアップ

    影響範囲:
        - アプリケーション停止時
    """
    logger.info("Application shutting down")


@app.get("/")
def root():
    """
    ルートエンドポイント

    Returns:
        dict: アプリケーション情報
    """
    return {
        "message": "demo-api is running",
        "version": "1.0.0",
        "docs": "/docs"
    }


if __name__ == "__main__":
    import uvicorn

    # Uvicorn起動（開発環境用）
    # 本番環境ではDockerfileでCMDとして実行
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8080,
        reload=True,  # 開発環境のみ
        log_level="info"
    )
