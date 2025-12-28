# datadog_middleware.py - Datadog APM統合 詳細設計

## 📋 ドキュメント情報

| 項目 | 内容 |
|------|------|
| ドキュメント名 | datadog_middleware.py - Datadog APM統合 詳細設計 |
| バージョン | 1.0 |
| 作成日 | 2025-12-28 |
| 作成者 | App-Architect |

---

## 🎯 モジュール概要

### 責務
- Datadog APM (ddtrace) の初期化とトレース送信
- カスタムタグ設定（tenant_id 等）

### 主要機能
1. **ddtrace 初期化**: FastAPI アプリケーションへの自動計装
2. **カスタムタグ設定**: tenant_id をトレースに追加
3. **トレース送信**: Datadog Agent にトレース送信

### 依存関係
- **使用技術**: ddtrace (Datadog APM Python SDK)
- **依存先**: なし
- **依存元**: FastAPI アプリケーション（main.py）

---

## 📊 関数設計

### 関数: `setup_datadog(app: FastAPI)`

**目的**: Datadog APM を初期化

**関数シグネチャ**:
```python
from ddtrace import patch_all, tracer
from ddtrace.contrib.fastapi import get_middleware
from fastapi import FastAPI
import os

def setup_datadog(app: FastAPI) -> None:
    """
    Datadog APM を初期化

    Args:
        app (FastAPI): FastAPI アプリケーションインスタンス

    環境変数:
        DD_SERVICE: サービス名（デフォルト: demo-api）
        DD_ENV: 環境名（デフォルト: poc）
        DD_VERSION: バージョン（デフォルト: 1.0.0）
        DD_AGENT_HOST: Datadog Agent ホスト（デフォルト: localhost）
        DD_TRACE_AGENT_PORT: Datadog Agent ポート（デフォルト: 8126）
    """
    # 環境変数設定
    os.environ.setdefault("DD_SERVICE", "demo-api")
    os.environ.setdefault("DD_ENV", "poc")
    os.environ.setdefault("DD_VERSION", "1.0.0")
    os.environ.setdefault("DD_AGENT_HOST", "localhost")
    os.environ.setdefault("DD_TRACE_AGENT_PORT", "8126")

    # 自動計装を有効化
    patch_all()

    # FastAPI ミドルウェアを追加
    app.add_middleware(get_middleware(tracer))
```

**処理フロー**:
```
1. 環境変数設定（DD_SERVICE, DD_ENV, DD_VERSION）
2. patch_all() で自動計装を有効化
3. FastAPI ミドルウェアを追加
```

---

## 📐 カスタムタグ設定

### tenant_id タグ追加（Controller 層で実施）

```python
from ddtrace import tracer

@app.get("/{tenant_id}/items")
def get_items(tenant_id: str):
    # カスタムタグ設定
    span = tracer.current_span()
    if span:
        span.set_tag("tenant_id", tenant_id)

    # 正常処理
    ...
```

---

## 📊 Datadog トレース例

```json
{
  "service": "demo-api",
  "env": "poc",
  "version": "1.0.0",
  "resource": "GET /{tenant_id}/items",
  "tags": {
    "tenant_id": "tenant-a",
    "http.method": "GET",
    "http.status_code": 200,
    "http.url": "/tenant-a/items"
  },
  "duration": 45,
  "spans": [
    {
      "name": "http.request",
      "duration": 45
    },
    {
      "name": "items_service.get_items",
      "duration": 30
    },
    {
      "name": "postgres.query",
      "duration": 25
    }
  ]
}
```

---

## 🧪 テスト方針

### 統合テスト

```python
def test_datadog_tracing(client: TestClient):
    """
    Datadog APM トレース送信テスト

    検証項目:
        - トレースIDがレスポンスヘッダに含まれるか
    """
    response = client.get("/tenant-a/health")

    assert response.status_code == 200
    assert "x-datadog-trace-id" in response.headers
```

---

## 📝 実装時の注意事項

### 環境変数設定（ECS タスク定義）

```json
{
  "environment": [
    {"name": "DD_SERVICE", "value": "demo-api"},
    {"name": "DD_ENV", "value": "poc"},
    {"name": "DD_VERSION", "value": "1.0.0"},
    {"name": "DD_AGENT_HOST", "value": "localhost"},
    {"name": "DD_TRACE_AGENT_PORT", "value": "8126"}
  ]
}
```

---

## 📝 改訂履歴

| 日付 | バージョン | 変更内容 | 作成者 |
|------|-----------|----------|--------|
| 2025-12-28 | 1.0 | 初版作成 | App-Architect |
