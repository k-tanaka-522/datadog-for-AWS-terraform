"""
ヘルスチェックコントローラー

目的: L2/L3 E2E監視対応、ALB→ECS→RDS疎通確認
影響範囲: ALBヘルスチェック、Datadog Synthetic Monitoring
前提条件: database.py（DB接続）、tenant_service.py（テナント検証）
"""

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import JSONResponse
from sqlalchemy.orm import Session
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy import text
from datetime import datetime
from ddtrace import tracer

from repositories.database import get_db
from services.tenant_service import TenantService
from infrastructure.logger import get_logger

logger = get_logger()
router = APIRouter()


def check_db_connection(db: Session, query: str = "SELECT 1") -> bool:
    """
    データベース接続確認（ヘルスチェック用）

    Args:
        db (Session): データベースセッション
        query (str): 実行するクエリ（デフォルト: SELECT 1）

    Returns:
        bool: True（接続成功）、False（接続失敗）
    """
    try:
        db.execute(text(query))
        return True
    except Exception:
        return False


@router.get("/health")
def health_check_service(db: Session = Depends(get_db)):
    """
    サービスレベルヘルスチェック（L2 E2E監視用）

    目的:
        - ALB → ECS → RDS の全体疎通確認
        - Datadog Synthetic Monitoring による定期監視
        - FR-003-0（L2 E2E監視）対応

    影響範囲:
        - ALBヘルスチェック
        - Datadog Synthetic Monitoring

    Args:
        db (Session): データベースセッション

    Returns:
        dict: ヘルスチェック結果
            - status: "ok" | "error"
            - database: "connected" | "disconnected"
            - timestamp: ISO 8601形式

    Raises:
        HTTPException(503): DB接続失敗時
    """
    # Datadog カスタムタグ設定
    span = tracer.current_span()
    if span:
        span.set_tag("health_check_level", "L2")
        span.set_tag("health_check_type", "service")

    # RDS接続確認（SELECT 1で疎通確認）
    try:
        db_status = check_db_connection(db, query="SELECT 1")
    except SQLAlchemyError as e:
        # エラーログ出力（構造化ログ、JSON形式）
        logger.error(
            "DB connection failed in health check",
            exc_info=True,
            extra={
                "health_check_level": "L2",
                "health_check_type": "service",
                "error_type": "db_connection_failed",
                "severity": "error"
            }
        )

        # Datadog APM にエラートレースを送信
        if span:
            span.set_tag("error", True)
            span.set_tag("error.type", "db_connection_failed")
            span.set_tag("error.message", str(e))

        return JSONResponse(
            status_code=503,
            content={
                "status": "error",
                "database": "disconnected",
                "timestamp": datetime.utcnow().isoformat() + "Z"
            }
        )

    if not db_status:
        # エラーログ出力
        logger.error(
            "DB health check failed",
            extra={
                "health_check_level": "L2",
                "health_check_type": "service",
                "error_type": "db_connection_failed",
                "severity": "error"
            }
        )

        return JSONResponse(
            status_code=503,
            content={
                "status": "error",
                "database": "disconnected",
                "timestamp": datetime.utcnow().isoformat() + "Z"
            }
        )

    # 正常レスポンス
    return {
        "status": "ok",
        "database": "connected",
        "timestamp": datetime.utcnow().isoformat() + "Z"
    }


@router.get("/{tenant_id}/health")
def health_check_tenant(tenant_id: str, db: Session = Depends(get_db)):
    """
    テナント別ヘルスチェック（L3 E2E監視用）

    目的:
        - テナント固有のDB接続確認（tenant_idでフィルタしたクエリ実行）
        - Datadog Synthetic Monitoring によるテナント別監視
        - FR-003-1（L3 E2E監視）対応

    影響範囲:
        - Datadog Synthetic Monitoring（テナント別）

    Args:
        tenant_id (str): テナントID
        db (Session): データベースセッション

    Returns:
        dict: ヘルスチェック結果
            - status: "ok" | "error"
            - tenant_id: str
            - database: "connected" | "disconnected"
            - timestamp: ISO 8601形式

    Raises:
        HTTPException(400): 無効なテナントID
        HTTPException(503): DB接続失敗時
    """
    # テナントID検証
    TenantService.validate_tenant(tenant_id)

    # Datadog カスタムタグ設定
    span = tracer.current_span()
    if span:
        span.set_tag("health_check_level", "L3")
        span.set_tag("health_check_type", "tenant")
        span.set_tag("tenant.id", tenant_id)

    # RDS接続確認（テナント固有クエリ）
    # SQLインジェクション対策: パラメータ化クエリを使用
    try:
        query = text("SELECT 1 FROM items WHERE tenant_id = :tenant_id LIMIT 1")
        db.execute(query, {"tenant_id": tenant_id})
        db_status = True
    except SQLAlchemyError as e:
        # エラーログ出力
        logger.error(
            f"DB connection failed in tenant health check for {tenant_id}",
            exc_info=True,
            extra={
                "tenant_id": tenant_id,
                "health_check_level": "L3",
                "health_check_type": "tenant",
                "error_type": "db_connection_failed",
                "severity": "error"
            }
        )

        # Datadog APM にエラートレースを送信
        if span:
            span.set_tag("error", True)
            span.set_tag("error.type", "db_connection_failed")
            span.set_tag("error.message", str(e))

        return JSONResponse(
            status_code=503,
            content={
                "status": "error",
                "tenant_id": tenant_id,
                "database": "disconnected",
                "timestamp": datetime.utcnow().isoformat() + "Z"
            }
        )

    # 正常レスポンス
    return {
        "status": "ok",
        "tenant_id": tenant_id,
        "database": "connected",
        "timestamp": datetime.utcnow().isoformat() + "Z"
    }
