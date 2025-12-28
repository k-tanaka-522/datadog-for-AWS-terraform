# health_controller.py - ヘルスチェック 詳細設計

## 📋 ドキュメント情報

| 項目 | 内容 |
|------|------|
| ドキュメント名 | health_controller.py - ヘルスチェック 詳細設計 |
| バージョン | 1.2 |
| 作成日 | 2025-12-28 |
| 作成者 | App-Architect |

---

## 🎯 モジュール概要

### 責務
- サービスレベルヘルスチェック処理（L2 E2E監視対応）
- テナント別ヘルスチェック処理（L3 E2E監視対応）
- RDS接続確認
- FR-003-0（L2 E2E監視）、FR-003-1（L3 E2E監視）対応

### 依存関係
- **依存先**: `tenant_service.py`, `database.py`
- **依存元**: FastAPI Router

---

## 📐 エンドポイント設計

### 1. GET /health（サービスレベル）

**関数シグネチャ**:
```python
from fastapi import APIRouter, HTTPException, Depends
from fastapi.responses import JSONResponse
from sqlalchemy.orm import Session
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError
from database import get_db
from ddtrace import tracer
import datetime

router = APIRouter()

@router.get("/health")
def health_check_service(
    db: Session = Depends(get_db)
):
    """
    サービスレベルヘルスチェック（L2 E2E監視用）

    Args:
        db (Session): データベースセッション

    Returns:
        dict: ヘルスチェック結果

    Raises:
        HTTPException(503): DB接続失敗
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
                "timestamp": datetime.datetime.utcnow().isoformat() + "Z"
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
                "timestamp": datetime.datetime.utcnow().isoformat() + "Z"
            }
        )

    # 正常レスポンス
    return {
        "status": "ok",
        "database": "connected",
        "timestamp": datetime.datetime.utcnow().isoformat() + "Z"
    }
```

**処理フロー**:
```
1. Datadog カスタムタグ設定（health_check_level=L2, health_check_type=service）
2. RDS接続確認（SELECT 1）（try-exceptでSQLAlchemyErrorをキャッチ）
3. 正常時: 200 OK、DB接続失敗時: 503 Service Unavailable + エラーログ出力
```

**RDS疎通確認**:
- クエリ: `SELECT 1`
- 目的: ALB → ECS → RDS の全体の疎通を確認（テナント固有データは不要）

**エラーログ出力（JSON形式）**:
```json
{
  "timestamp": "2025-12-28T10:00:00Z",
  "level": "ERROR",
  "message": "DB connection failed in health check",
  "health_check_level": "L2",
  "health_check_type": "service",
  "error_type": "db_connection_failed",
  "severity": "error",
  "trace_id": "abc123",
  "span_id": "def456"
}
```

**Datadog監視**:
- **Datadog Logs**: `severity:error error_type:db_connection_failed health_check_level:L2`
- **Datadog Synthetic Monitoring**: `/health` エンドポイントで503を検知
- **アラート条件**: 連続して503が返される場合にアラート

---

### 2. GET /{tenant_id}/health（テナント別）

**関数シグネチャ**:
```python
from services.tenant_service import TenantService
from logger import setup_logger

tenant_service = TenantService()
logger = setup_logger("demo-api")

@router.get("/{tenant_id}/health")
def health_check_tenant(
    tenant_id: str,
    db: Session = Depends(get_db)
):
    """
    テナント別ヘルスチェック（L3 E2E監視用）

    Args:
        tenant_id (str): テナントID
        db (Session): データベースセッション

    Returns:
        dict: ヘルスチェック結果

    Raises:
        HTTPException(400): 無効なテナント
        HTTPException(503): DB接続失敗
    """
    # Datadog カスタムタグ設定
    span = tracer.current_span()
    if span:
        span.set_tag("tenant_id", tenant_id)
        span.set_tag("health_check_level", "L3")
        span.set_tag("health_check_type", "tenant")

    # テナント検証
    if not tenant_service.validate_tenant(tenant_id):
        logger.warning(
            f"Invalid tenant in health check: {tenant_id}",
            extra={
                "tenant_id": tenant_id,
                "health_check_level": "L3",
                "error_type": "invalid_tenant"
            }
        )

        raise HTTPException(
            status_code=400,
            detail={
                "error": {
                    "code": "INVALID_TENANT",
                    "message": f"Tenant '{tenant_id}' is not valid",
                    "field": "tenant_id"
                }
            }
        )

    # RDS接続確認（テナント固有データで疎通確認）
    # ⚠️ SQLインジェクション対策: プレースホルダを使用
    try:
        db_status = check_db_connection(
            db,
            query=text("SELECT 1 FROM items WHERE tenant_id = :tenant_id LIMIT 1"),
            params={"tenant_id": tenant_id}
        )
    except SQLAlchemyError as e:
        # エラーログ出力（構造化ログ、JSON形式）
        logger.error(
            f"DB connection failed for tenant {tenant_id} in health check",
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
                "timestamp": datetime.datetime.utcnow().isoformat() + "Z"
            }
        )

    if not db_status:
        # エラーログ出力
        logger.error(
            f"DB health check failed for tenant {tenant_id}",
            extra={
                "tenant_id": tenant_id,
                "health_check_level": "L3",
                "health_check_type": "tenant",
                "error_type": "db_connection_failed",
                "severity": "error"
            }
        )

        return JSONResponse(
            status_code=503,
            content={
                "status": "error",
                "tenant_id": tenant_id,
                "database": "disconnected",
                "timestamp": datetime.datetime.utcnow().isoformat() + "Z"
            }
        )

    # 正常レスポンス
    return {
        "status": "ok",
        "tenant_id": tenant_id,
        "database": "connected",
        "timestamp": datetime.datetime.utcnow().isoformat() + "Z"
    }
```

**処理フロー**:
```
1. Datadog カスタムタグ設定（tenant_id, health_check_level=L3, health_check_type=tenant）
2. テナント検証（TenantService）
3. RDS接続確認（SELECT 1 FROM items WHERE tenant_id = :tenant_id LIMIT 1）（プレースホルダ使用）
4. 正常時: 200 OK、DB接続失敗時: 503 Service Unavailable + エラーログ出力
```

**RDS疎通確認**:
- クエリ: `SELECT 1 FROM items WHERE tenant_id = :tenant_id LIMIT 1`（プレースホルダ使用）
- 目的: ALB → ECS → RDS（テナント固有データ）の疎通を確認

**エラーログ出力（JSON形式）**:
```json
{
  "timestamp": "2025-12-28T10:00:00Z",
  "level": "ERROR",
  "message": "DB connection failed for tenant tenant-a in health check",
  "tenant_id": "tenant-a",
  "health_check_level": "L3",
  "health_check_type": "tenant",
  "error_type": "db_connection_failed",
  "severity": "error",
  "trace_id": "abc123",
  "span_id": "def456"
}
```

**Datadog監視**:
- **Datadog Logs**: `severity:error error_type:db_connection_failed tenant_id:tenant-a health_check_level:L3`
- **Datadog Synthetic Monitoring**: `/{tenant_id}/health` エンドポイントで503を検知
- **アラート条件**: 特定テナントで連続して503が返される場合にアラート

---

## 📊 レスポンス例

### サービスレベル（GET /health）

#### 成功（200 OK）

```json
{
  "status": "ok",
  "database": "connected",
  "timestamp": "2025-12-28T12:34:56.789Z"
}
```

#### DB接続失敗（503 Service Unavailable）

```json
{
  "status": "error",
  "database": "disconnected",
  "timestamp": "2025-12-28T12:34:56.789Z"
}
```

---

### テナント別（GET /{tenant_id}/health）

#### 成功（200 OK）

```json
{
  "status": "ok",
  "tenant_id": "tenant-a",
  "database": "connected",
  "timestamp": "2025-12-28T12:34:56.789Z"
}
```

#### DB接続失敗（503 Service Unavailable）

```json
{
  "status": "error",
  "tenant_id": "tenant-a",
  "database": "disconnected",
  "timestamp": "2025-12-28T12:34:56.789Z"
}
```

#### 無効なテナント（400 Bad Request）

```json
{
  "error": {
    "code": "INVALID_TENANT",
    "message": "Tenant 'tenant-x' is not valid",
    "field": "tenant_id"
  }
}
```

---

## 🔧 database.py の更新

### check_db_connection 関数

```python
from sqlalchemy.orm import Session
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy import text
from ddtrace import tracer

def check_db_connection(db: Session, *, query: str = "SELECT 1", params: dict = None) -> bool:
    """
    データベース接続確認

    Args:
        db (Session): データベースセッション
        query (str): 疎通確認クエリ（デフォルト: SELECT 1）
        params (dict): クエリパラメータ（プレースホルダ使用時）

    Returns:
        bool: 接続成功時 True、失敗時 False

    注意:
        - SQLインジェクション対策のため、プレースホルダを使用してください
        - 例: check_db_connection(db, query=text("SELECT 1 FROM items WHERE tenant_id = :tenant_id"), params={"tenant_id": "tenant-a"})
    """
    try:
        if params:
            # プレースホルダ使用
            result = db.execute(text(query), params)
        else:
            # プレースホルダなし（単純なSELECT 1等）
            result = db.execute(text(query))
        result.fetchone()
        return True
    except SQLAlchemyError as e:
        # ログ出力（Datadog APM にエラートレースを送信）
        span = tracer.current_span()
        if span:
            span.set_tag("error", True)
            span.set_tag("error.type", "db_connection_failed")
            span.set_tag("error.message", str(e))
        return False
```

**重要な変更点**:
1. **関数シグネチャ統一**: `def check_db_connection(db: Session, *, query: str = "SELECT 1", params: dict = None) -> bool:`
2. **SQLインジェクション対策**: `text()` と `params` でプレースホルダ使用
3. **エラーハンドリング**: `try-except` で `SQLAlchemyError` をキャッチ
4. **Datadog APM連携**: エラートレースを送信

---

## 🚨 起動失敗時のエラーログ設計

### A. サービス起動失敗時

**シナリオ1: DB接続失敗でアプリが起動できない**

**実装場所**: `database.py` または `main.py` の startup イベント

```python
from logger import setup_logger

logger = setup_logger("demo-api")

@app.on_event("startup")
async def startup_event():
    """
    アプリケーション起動時の処理
    """
    try:
        # DB接続確認
        db = SessionLocal()
        db.execute(text("SELECT 1"))
        db.close()

        logger.info("Application started successfully")
    except Exception as e:
        # エラーログ出力（構造化ログ、JSON形式）
        logger.error(
            "Application startup failed: DB connection failed",
            exc_info=True,
            extra={
                "startup_phase": "db_connection_check",
                "error_type": "db_connection_failed",
                "severity": "error"
            }
        )

        # ECS Task を停止（異常終了）
        raise RuntimeError("DB connection failed at startup") from e
```

**エラーログ出力（JSON形式）**:
```json
{
  "timestamp": "2025-12-28T10:00:00Z",
  "level": "ERROR",
  "message": "Application startup failed: DB connection failed",
  "startup_phase": "db_connection_check",
  "error_type": "db_connection_failed",
  "severity": "error",
  "exception": "OperationalError: connection failed"
}
```

**Datadog監視**:
- **Datadog Logs**: `severity:error error_type:db_connection_failed startup_phase:db_connection_check`
- **ECS Task停止**: CloudWatch Logsに出力、ECS Serviceが自動再起動
- **アラート条件**: 起動失敗が複数回続く場合にアラート

---

**シナリオ2: 環境変数未設定でアプリが起動できない**

**実装場所**: `database.py` または `settings.py`

```python
import os
from logger import setup_logger

logger = setup_logger("demo-api")

def get_database_url() -> str:
    """
    DATABASE_URL環境変数を取得
    """
    database_url = os.getenv("DATABASE_URL")

    if not database_url or database_url.strip() == "":
        # エラーログ出力（構造化ログ、JSON形式）
        logger.error(
            "Application startup failed: DATABASE_URL not set",
            extra={
                "startup_phase": "env_validation",
                "error_type": "missing_env_var",
                "env_var": "DATABASE_URL",
                "severity": "error"
            }
        )

        raise RuntimeError("DATABASE_URL environment variable is not set")

    return database_url
```

**エラーログ出力（JSON形式）**:
```json
{
  "timestamp": "2025-12-28T10:00:00Z",
  "level": "ERROR",
  "message": "Application startup failed: DATABASE_URL not set",
  "startup_phase": "env_validation",
  "error_type": "missing_env_var",
  "env_var": "DATABASE_URL",
  "severity": "error"
}
```

**Datadog監視**:
- **Datadog Logs**: `severity:error error_type:missing_env_var env_var:DATABASE_URL`

---

## 📝 改訂履歴

| 日付 | バージョン | 変更内容 | 作成者 |
|------|-----------|----------|--------|
| 2025-12-28 | 1.0 | 初版作成 | App-Architect |
| 2025-12-28 | 1.1 | E2E監視対応: `/health` エンドポイント追加、`/{tenant_id}/health` にRDS疎通確認クエリを明記 | App-Architect |
| 2025-12-28 | 1.2 | Coderレビュー対応: SQLインジェクション対策（プレースホルダ使用）、check_db_connection関数シグネチャ統一、エラーハンドリング追加、起動失敗時のエラーログ設計追加 | App-Architect |
