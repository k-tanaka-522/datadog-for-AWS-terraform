"""
障害シミュレーションコントローラー

目的: エラー/遅延シミュレーション、Datadog監視データ生成
影響範囲: シミュレーションエンドポイント
前提条件: MonitoringService、TenantService
"""

from fastapi import APIRouter
from pydantic import BaseModel, Field
from typing import Optional
from ddtrace import tracer

from services.tenant_service import TenantService
from services.monitoring_service import MonitoringService
from infrastructure.logger import get_logger

logger = get_logger()
router = APIRouter()


class ErrorSimulateRequest(BaseModel):
    """エラーシミュレーションリクエスト"""
    error_type: Optional[str] = Field("generic", description="エラー種別（generic, database, external_api）")


class LatencySimulateRequest(BaseModel):
    """遅延シミュレーションリクエスト"""
    duration_ms: int = Field(1000, ge=100, le=10000, description="遅延時間（ミリ秒）")


@router.post("/{tenant_id}/simulate/error")
def simulate_error(tenant_id: str, request: ErrorSimulateRequest):
    """
    エラーシミュレーション

    目的:
        - Datadog エラートラッキングテスト
        - アラート設定テスト

    Args:
        tenant_id (str): テナントID
        request (ErrorSimulateRequest): エラーシミュレーションリクエスト

    Raises:
        Exception: 常に例外を発生（エラーシミュレーション）
    """
    # テナントID検証
    TenantService.validate_tenant(tenant_id)

    # Datadog カスタムタグ設定
    span = tracer.current_span()
    if span:
        span.set_tag("tenant.id", tenant_id)
        span.set_tag("operation", "simulate_error")
        span.set_tag("error_type", request.error_type)

    # ログ出力
    logger.info(
        f"Simulating error for tenant {tenant_id}",
        extra={
            "tenant_id": tenant_id,
            "error_type": request.error_type
        }
    )

    # エラーシミュレーション実行（例外発生）
    MonitoringService.simulate_error(tenant_id, request.error_type)


@router.post("/{tenant_id}/simulate/latency")
def simulate_latency(tenant_id: str, request: LatencySimulateRequest):
    """
    遅延シミュレーション

    目的:
        - Datadog APM レイテンシトラッキングテスト
        - パフォーマンス監視テスト

    Args:
        tenant_id (str): テナントID
        request (LatencySimulateRequest): 遅延シミュレーションリクエスト

    Returns:
        dict: シミュレーション結果
            - tenant_id: str
            - latency_ms: int
            - message: str
    """
    # テナントID検証
    TenantService.validate_tenant(tenant_id)

    # Datadog カスタムタグ設定
    span = tracer.current_span()
    if span:
        span.set_tag("tenant.id", tenant_id)
        span.set_tag("operation", "simulate_latency")
        span.set_tag("latency_ms", request.duration_ms)

    # ログ出力
    logger.info(
        f"Simulating latency for tenant {tenant_id}",
        extra={
            "tenant_id": tenant_id,
            "latency_ms": request.duration_ms
        }
    )

    # 遅延シミュレーション実行
    result = MonitoringService.simulate_latency(tenant_id, request.duration_ms)

    return result
