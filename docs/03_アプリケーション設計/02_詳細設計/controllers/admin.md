# admin_controller.py - 管理機能 詳細設計

## 📋 ドキュメント情報

| 項目 | 内容 |
|------|------|
| ドキュメント名 | admin_controller.py - 管理機能 詳細設計 |
| バージョン | 1.1 |
| 作成日 | 2025-12-28 |
| 作成者 | App-Architect |

---

## 🎯 モジュール概要

### 責務
- ECSタスク停止テスト（FR-002-2 L2監視）
- 管理機能（本番環境では認証必須）

### 依存関係
- **依存先**: なし
- **依存元**: FastAPI Router

---

## 📐 エンドポイント設計

### POST /admin/shutdown

**関数シグネチャ**:
```python
import os
import asyncio
import datetime
from fastapi import APIRouter, BackgroundTasks
from logger import setup_logger

router = APIRouter()
logger = setup_logger()

@router.post("/admin/shutdown")
def shutdown(background_tasks: BackgroundTasks):
    """
    ECSタスク停止テスト

    Args:
        background_tasks (BackgroundTasks): FastAPI BackgroundTasks

    Returns:
        dict: shutdownステータス

    注意:
        - レスポンス送信後、BackgroundTasksでプロセス終了
        - FR-002-2: ECS Task 停止監視用
    """
    # ログ出力
    logger.warning(
        "Shutdown requested via /admin/shutdown",
        extra={
            "admin_action": "shutdown",
            "timestamp": datetime.datetime.utcnow().isoformat() + "Z"
        }
    )

    # バックグラウンドタスクでプロセス終了を登録
    background_tasks.add_task(shutdown_task)

    # レスポンス返却（200 OK）
    return {
        "status": "shutting_down",
        "message": "ECS task will be terminated",
        "timestamp": datetime.datetime.utcnow().isoformat() + "Z"
    }

async def shutdown_task():
    """
    プロセス終了タスク（レスポンス送信後に実行）

    注意:
        - os._exit(0) を使用してプロセスを即座に終了
        - ECSが異常終了と判断し、再起動する
    """
    # レスポンス送信を確実に待つ
    await asyncio.sleep(0.1)

    logger.warning("Shutting down now")

    # 強制終了（ECSが異常終了と判断し、再起動）
    os._exit(0)
```

**処理フロー**:
```
1. ログ出力（WARNING レベル）
2. FastAPI BackgroundTasks でプロセス終了タスクを登録
3. レスポンス返却（200 OK）
4. バックグラウンドタスクでプロセス終了（0.1秒待機後に os._exit(0)）
```

**重要**:
- `os._exit(0)` は強制終了のため、ECS が異常終了と判断し、再起動する
- FastAPI `BackgroundTasks` を使用してレスポンス送信後にプロセス終了
- `import asyncio` を追加

---

## 📊 レスポンス例

### 成功（200 OK）

```json
{
  "status": "shutting_down",
  "message": "ECS task will be terminated",
  "timestamp": "2025-12-28T10:15:00Z"
}
```

---

## 📝 実装時の注意事項

### 本番環境での認証

**PoC では認証なし**:
```python
@router.post("/admin/shutdown")
def shutdown(background_tasks: BackgroundTasks):
    ...
```

**本番環境では API Key 認証必須**:
```python
from fastapi import Header, HTTPException

@router.post("/admin/shutdown")
def shutdown(background_tasks: BackgroundTasks, x_api_key: str = Header(...)):
    if x_api_key != os.getenv("ADMIN_API_KEY"):
        raise HTTPException(status_code=403, detail="Forbidden")
    ...
```

---

## 📝 改訂履歴

| 日付 | バージョン | 変更内容 | 作成者 |
|------|-----------|----------|--------|
| 2025-12-28 | 1.0 | 初版作成 | App-Architect |
| 2025-12-28 | 1.1 | Coderレビュー対応: FastAPI BackgroundTasks使用に修正、import asyncio 追加 | App-Architect |
