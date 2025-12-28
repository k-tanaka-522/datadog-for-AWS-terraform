# database.py - データベースセッション管理 詳細設計

## 📋 ドキュメント情報

| 項目 | 内容 |
|------|------|
| ドキュメント名 | database.py - データベースセッション管理 詳細設計 |
| バージョン | 1.0 |
| 作成日 | 2025-12-28 |
| 作成者 | App-Architect |

---

## 🎯 モジュール概要

### 責務
PostgreSQL RDS への接続管理とセッション提供

### 主要機能
1. **セッション管理**: SQLAlchemy セッションの作成・破棄
2. **接続プール**: データベース接続プール管理
3. **DB初期化**: テーブル作成（開発環境のみ）

### 依存関係
- **使用技術**: SQLAlchemy 2.0+, psycopg2
- **依存先**: `settings.py`（環境変数）, `item.py`（Model）
- **依存元**: `items_repository.py`, FastAPI Dependency Injection

---

## 📊 モジュール設計

### グローバル変数

```python
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, Session
from typing import Generator
import os

# データベース接続URL（環境変数から取得）
DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql://demo_user:demo_password@localhost:5432/demo_db"
)

# エンジン作成（接続プール設定）
engine = create_engine(
    DATABASE_URL,
    pool_size=10,          # 接続プールサイズ
    max_overflow=20,       # 最大接続数超過時の追加接続数
    pool_pre_ping=True,    # 接続前にヘルスチェック
    echo=False,            # SQLログ出力（本番環境では False）
)

# セッションファクトリ
SessionLocal = sessionmaker(
    autocommit=False,
    autoflush=False,
    bind=engine
)
```

---

## 🔧 関数詳細設計

### 関数一覧

| 関数 | 説明 | 戻り値 |
|------|------|--------|
| `get_db()` | データベースセッション取得（FastAPI Dependency） | Generator[Session] |
| `init_db()` | データベース初期化（テーブル作成） | None |
| `check_db_connection()` | データベース接続確認 | bool |

---

## 📐 関数詳細

### 1. `get_db()`

**目的**: FastAPI の Dependency Injection でセッションを提供

**関数シグネチャ**:
```python
def get_db() -> Generator[Session, None, None]:
    """
    データベースセッションを取得する（FastAPI Dependency Injection 用）

    目的:
        - FastAPI エンドポイントにセッションを注入
        - リクエスト終了時に自動的にセッションをクローズ

    影響範囲:
        - すべての Controller（Depends(get_db) で使用）
        - すべての Repository（セッションを受け取る）

    前提条件:
        - DATABASE_URL が正しく設定されている
        - PostgreSQL RDS が起動している

    Yields:
        Session: SQLAlchemy セッション

    例外:
        OperationalError: DB接続失敗時
    """
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
```

**処理フロー**:
```python
1. SessionLocal() でセッション生成
2. yield でセッションを返却（Controller に注入）
3. try-finally で確実にセッションをクローズ
```

**使用例（Controller での利用）**:
```python
from fastapi import Depends
from sqlalchemy.orm import Session

@app.get("/items")
def get_items(db: Session = Depends(get_db)):
    # db はリクエストごとに新しいセッション
    items = db.query(Item).all()
    return items
```

---

### 2. `init_db()`

**目的**: データベース初期化（テーブル作成）

**関数シグネチャ**:
```python
from models.item import Base

def init_db() -> None:
    """
    データベースを初期化する（テーブル作成）

    目的:
        - 開発環境でのテーブル自動作成
        - テスト環境でのDB初期化

    影響範囲:
        - items テーブルの作成

    前提条件:
        - PostgreSQL RDS が起動している
        - Base に全 Model が登録されている

    注意:
        - 本番環境では使用しない（Alembic によるマイグレーション推奨）
    """
    Base.metadata.create_all(bind=engine)
```

**処理フロー**:
```python
1. Base.metadata.create_all() でテーブル作成
2. すでにテーブルが存在する場合はスキップ
```

**使用例（main.py での利用）**:
```python
from database import init_db

# アプリケーション起動時に実行
@app.on_event("startup")
async def startup_event():
    init_db()
```

---

### 3. `check_db_connection()`

**目的**: データベース接続確認（ヘルスチェック用）

**関数シグネチャ**:
```python
def check_db_connection() -> bool:
    """
    データベース接続を確認する

    目的:
        - ヘルスチェックエンドポイントで使用
        - DB接続障害の早期検知

    Returns:
        bool: True（接続成功）、False（接続失敗）

    例外:
        なし（内部でキャッチして False を返す）
    """
    try:
        db = SessionLocal()
        db.execute("SELECT 1")
        db.close()
        return True
    except Exception as e:
        # ログ出力（詳細は logger.py 参照）
        print(f"DB connection check failed: {e}")
        return False
```

**処理フロー**:
```python
1. SessionLocal() でセッション生成
2. SELECT 1 でDB接続確認
3. 成功したら True、失敗したら False
4. finally でセッションクローズ
```

---

## 🔄 シーケンス図

### セッション取得フロー（FastAPI Dependency Injection）

```mermaid
sequenceDiagram
    participant Client as クライアント
    participant FastAPI as FastAPI Router
    participant Dependency as get_db()
    participant SessionLocal as SessionLocal
    participant Controller as items_controller
    participant DB as PostgreSQL

    Client->>FastAPI: GET /items
    FastAPI->>Dependency: get_db() 呼び出し
    Dependency->>SessionLocal: SessionLocal()
    SessionLocal-->>Dependency: session
    Dependency-->>FastAPI: yield session
    FastAPI->>Controller: get_items(db=session)
    Controller->>DB: db.query(Item).all()
    DB-->>Controller: items
    Controller-->>FastAPI: items
    FastAPI-->>Dependency: リクエスト終了
    Dependency->>SessionLocal: session.close()
    FastAPI-->>Client: レスポンス
```

---

## 📊 データ構造

### 接続プール設定

```python
engine = create_engine(
    DATABASE_URL,
    pool_size=10,          # 常時維持する接続数
    max_overflow=20,       # pool_size を超えた場合の追加接続数
    pool_pre_ping=True,    # 接続前にSELECT 1でヘルスチェック
    echo=False,            # SQLログ出力（開発環境では True）
)
```

| パラメータ | 値 | 説明 |
|----------|-----|------|
| pool_size | 10 | 常時維持する接続数 |
| max_overflow | 20 | 最大接続数（pool_size + max_overflow = 30） |
| pool_pre_ping | True | 接続前にヘルスチェック（切断検知） |
| echo | False | SQLログ出力（本番環境では False） |

**NFR-003 対応**: テナント数 10〜100 に対応するため、接続プールサイズを 10 に設定。同時アクセスが多い場合は max_overflow で対応。

---

## 🚨 例外処理

### 発生する例外と対処方法

| 例外 | 発生条件 | 対処方法 |
|------|---------|---------|
| `OperationalError` | DB接続失敗、ネットワーク障害 | Controller 層でキャッチし、503 Service Unavailable を返す |
| `ProgrammingError` | SQL構文エラー、テーブル未存在 | Repository 層でキャッチし、500 Internal Server Error を返す |
| `TimeoutError` | 接続タイムアウト | pool_pre_ping で事前検知、リトライロジック実装 |

**重要**: database.py では例外をキャッチせず、上位層（Repository, Controller）に委譲。

---

## 🧪 テスト方針

### 単体テスト項目

#### 1. セッション取得テスト

```python
def test_get_db():
    """
    get_db() のテスト

    検証項目:
        - セッションが正しく生成されるか
        - finally でセッションがクローズされるか
    """
    db_gen = get_db()
    db = next(db_gen)

    assert db is not None
    assert isinstance(db, Session)

    # セッションクローズ確認
    try:
        next(db_gen)
    except StopIteration:
        pass  # 正常終了
```

#### 2. DB接続確認テスト

```python
def test_check_db_connection():
    """
    check_db_connection() のテスト

    検証項目:
        - DB接続成功時に True が返るか
    """
    result = check_db_connection()

    assert result is True
```

#### 3. DB接続失敗テスト（モック使用）

```python
from unittest.mock import patch

def test_check_db_connection_failure():
    """
    check_db_connection() の失敗テスト

    検証項目:
        - DB接続失敗時に False が返るか
    """
    with patch('database.SessionLocal') as mock_session:
        mock_session.side_effect = Exception("Connection failed")

        result = check_db_connection()

        assert result is False
```

---

## 📝 実装時の注意事項

### 1. 環境変数

**DATABASE_URL のフォーマット**:
```
postgresql://<user>:<password>@<host>:<port>/<database>
```

**例**:
```
postgresql://demo_user:demo_password@demo-db.xxxx.us-east-1.rds.amazonaws.com:5432/demo_db
```

**環境変数設定（ECS タスク定義）**:
```json
{
  "name": "DATABASE_URL",
  "value": "postgresql://..."
}
```

### 2. 接続プール設定

**NFR-003 対応**:
- テナント数 10〜100 に対応
- 同時アクセス数を考慮して pool_size=10, max_overflow=20

**本番環境でのチューニング**:
- 負荷テスト後に pool_size を調整
- RDS の max_connections を確認（デフォルト: 100）

### 3. マイグレーション

**開発環境**: `init_db()` でテーブル自動作成
**本番環境**: Alembic によるマイグレーション推奨

```bash
# Alembic 初期化
alembic init alembic

# マイグレーション作成
alembic revision --autogenerate -m "Create items table"

# マイグレーション実行
alembic upgrade head
```

### 4. ログ出力

**SQL ログ出力（開発環境のみ）**:
```python
engine = create_engine(
    DATABASE_URL,
    echo=True  # 開発環境では True
)
```

---

## 🔗 関連ドキュメント

| ドキュメント | パス | 目的 |
|-------------|------|------|
| 基本設計 - データモデル | `../../01_基本設計/03_データモデル.md` | ER図、テーブル定義 |
| 基本設計 - 実装方針 | `../../01_基本設計/06_実装方針.md` | ディレクトリ構成 |
| Python技術標準 | `.claude/docs/40_standards/41_app/languages/python.md` | コーディング規約 |
| Repository 詳細設計 | `./items_repository.md` | CRUD 操作 |

---

## 📝 改訂履歴

| 日付 | バージョン | 変更内容 | 作成者 |
|------|-----------|----------|--------|
| 2025-12-28 | 1.0 | 初版作成 | App-Architect |
