# simulate_controller.py - 障害シミュレーション 詳細設計

## 📋 ドキュメント情報

| 項目 | 内容 |
|------|------|
| ドキュメント名 | simulate_controller.py - 障害シミュレーション 詳細設計 |
| バージョン | 1.1 |
| 作成日 | 2025-12-28 |
| 作成者 | App-Architect |

---

## 🎯 モジュール概要

### 責務
- エラー発生テスト（FR-003-2）
- レイテンシ発生テスト（FR-003-3）

### 依存関係
- **依存先**: `tenant_service.py`, `monitoring_service.py`
- **依存元**: FastAPI Router

---

## 📐 エンドポイント設計

### 1. POST /{tenant_id}/simulate/error

**関数シグネチャ**:
```python
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from services.tenant_service import TenantService
from services.monitoring_service import MonitoringService
from logger import setup_logger
from ddtrace import tracer
import datetime

router = APIRouter()
tenant_service = TenantService()
logger = setup_logger()
monitoring_service = MonitoringService(logger)

class ErrorRequest(BaseModel):
    error_type: str  # "500", "timeout", "db_error"

@router.post("/{tenant_id}/simulate/error")
def simulate_error(tenant_id: str, request: ErrorRequest):
    """
    エラー発生シミュレーション

    Args:
        tenant_id (str): テナントID
        request (ErrorRequest): error_type を含むリクエスト

    Raises:
        HTTPException(400): 無効なテナント、無効なerror_type
        HTTPException(500): シミュレーションエラー
    """
    # Datadog カスタムタグ設定
    span = tracer.current_span()
    if span:
        span.set_tag("tenant_id", tenant_id)
        span.set_tag("error_type", request.error_type)

    # テナント検証
    if not tenant_service.validate_tenant(tenant_id):
        raise HTTPException(status_code=400, detail="Invalid tenant")

    # エラー種別検証
    valid_error_types = ["500", "timeout", "db_error"]
    if request.error_type not in valid_error_types:
        raise HTTPException(status_code=400, detail=f"Invalid error_type. Must be one of: {', '.join(valid_error_types)}")

    # エラー発生（常に例外を raise）
    monitoring_service.simulate_error(tenant_id, request.error_type)
```

**処理フロー**:
```
1. Datadog カスタムタグ設定
2. テナント検証
3. error_type 検証
4. MonitoringService.simulate_error() 呼び出し（常に例外を raise）
```

---

### 2. POST /{tenant_id}/simulate/latency

**関数シグネチャ**:
```python
class LatencyRequest(BaseModel):
    latency_ms: int  # 0〜10000

@router.post("/{tenant_id}/simulate/latency")
def simulate_latency(tenant_id: str, request: LatencyRequest):
    """
    レイテンシ発生シミュレーション

    Args:
        tenant_id (str): テナントID
        request (LatencyRequest): latency_ms を含むリクエスト

    Raises:
        HTTPException(400): 無効なテナント、無効なlatency_ms

    Returns:
        dict: レイテンシシミュレーション結果
    """
    # Datadog カスタムタグ設定
    span = tracer.current_span()
    if span:
        span.set_tag("tenant_id", tenant_id)
        span.set_tag("latency_ms", request.latency_ms)

    # テナント検証
    if not tenant_service.validate_tenant(tenant_id):
        raise HTTPException(status_code=400, detail="Invalid tenant")

    # レイテンシ検証
    if request.latency_ms < 0 or request.latency_ms > 10000:
        raise HTTPException(status_code=400, detail="latency_ms must be between 0 and 10000")

    # レイテンシ発生
    monitoring_service.simulate_latency(tenant_id, request.latency_ms)

    # 成功レスポンス
    return {
        "status": "success",
        "tenant_id": tenant_id,
        "latency_ms": request.latency_ms,
        "message": f"Simulated latency of {request.latency_ms}ms",
        "timestamp": datetime.datetime.utcnow().isoformat() + "Z"
    }
```

**処理フロー**:
```
1. Datadog カスタムタグ設定
2. テナント検証
3. latency_ms 検証
4. MonitoringService.simulate_latency() 呼び出し
5. 成功レスポンス返却
```

---

## 📝 改訂履歴

| 日付 | バージョン | 変更内容 | 作成者 |
|------|-----------|----------|--------|
| 2025-12-28 | 1.0 | 初版作成 | App-Architect |
| 2025-12-28 | 1.1 | Coderレビュー対応: datetime import 追加 | App-Architect |
