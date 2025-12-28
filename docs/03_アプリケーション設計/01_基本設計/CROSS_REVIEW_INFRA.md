# クロスレビュー結果（Infra → App）

## 📋 レビュー情報

| 項目 | 内容 |
|------|------|
| レビュー日 | 2025-12-28 |
| レビュアー | Infra-Architect |
| レビュー対象 | アプリケーション基本設計（6ファイル） |
| レビュー観点 | インフラ設計との整合性（RDS、ECS、ALB、Datadog、セキュリティ） |

---

## 🎯 総合評価

**✅ 条件付き承認**

アプリケーション設計は全体として適切に設計されており、インフラ設計との整合性も高いレベルで保たれています。
ただし、以下の**3点の改善提案**と**1点の確認事項**があります。

---

## 📊 レビュー結果サマリー

| 評価観点 | 評価 | コメント |
|---------|------|---------|
| 1. RDS構成との整合性 | ✅ | データモデル適切、接続設定良好 |
| 2. ECS構成との整合性 | ⚠️ | ポート8080明記、環境変数設計明確（Dockerfile内でポート設定を追記推奨） |
| 3. ALB構成との整合性 | ✅ | ヘルスチェックエンドポイント整合、パスルーティング不要 |
| 4. Datadog監視との整合性 | ⚠️ | L3テナント監視整合（ddtrace設定詳細化推奨） |
| 5. セキュリティ設計との整合性 | ⚠️ | 環境変数管理適切（RDS接続時のSSL/TLS明記推奨） |

---

## 1. RDS構成との整合性

### ✅ データモデル設計（03_データモデル.md）

**評価**: 適切

| 項目 | App設計 | Infra設計 | 整合性 |
|------|---------|----------|--------|
| データベース | PostgreSQL RDS | PostgreSQL RDS（Multi-AZ） | ✅ 一致 |
| テーブル | items（id, tenant_id, name, description, created_at, updated_at） | - | ✅ 適切 |
| インデックス | idx_tenant_id（tenant_id） | - | ✅ テナント別検索高速化に有効 |
| データ量 | 30件（10件/テナント） | - | ✅ PoC規模として適切 |

**コメント**:
- items テーブルのスキーマは適切です。
- `idx_tenant_id` インデックスは、テナント別検索（`GET /{tenant_id}/items`）を高速化するため有効です。
- データ量（30件）はPoC環境として適切であり、RDSインスタンスタイプ（既存Multi-AZ構成）に対して負荷は軽微です。

---

### ✅ RDS接続設定（コンポーネント設計、セキュリティ設計）

**評価**: 適切（SSL/TLS設定の明記推奨）

| 項目 | App設計 | Infra設計 | 整合性 |
|------|---------|----------|--------|
| ORM | SQLAlchemy | - | ✅ Python標準的ORM |
| 接続プール | SQLAlchemy Engine | - | ✅ 適切 |
| 接続文字列 | `DATABASE_URL` 環境変数 | - | ✅ 環境変数管理適切 |
| SSL/TLS | `sslmode=require`（セキュリティ設計に記載） | インフラ側でSSL強制推奨 | ⚠️ 詳細化推奨 |

**改善提案**:
1. **RDS接続時のSSL/TLS設定を明確化**
   - アプリケーション設計書（セキュリティ設計、実装方針）に、RDS接続文字列の`sslmode=require`を明記してください。
   - 例: `postgresql://user:password@rds-endpoint:5432/demo?sslmode=require`

2. **database.pyでのSSL証明書検証**
   - 本番環境では、RDS証明書の検証も推奨します（PoC環境では任意）。
   - 例: `sslrootcert=/path/to/rds-ca-cert.pem`

**理由**: インフラ側でRDSのSSL強制（`rds.force_ssl=1`）を検討しているため、アプリ側もSSL接続を前提とすべきです。

---

### ✅ トランザクション処理

**評価**: 適切

| 項目 | App設計 | Infra設計 | 整合性 |
|------|---------|----------|--------|
| トランザクション管理 | SQLAlchemy Session | - | ✅ 適切 |
| ロールバック | エラー時にロールバック | - | ✅ 適切 |

**コメント**: トランザクション制御はアプリケーション設計で適切に考慮されています。

---

## 2. ECS構成との整合性

### ✅ コンテナポート設定（Dockerfile、実装方針）

**評価**: 適切（Dockerfile内でポート設定を追記推奨）

| 項目 | App設計 | Infra設計 | 整合性 |
|------|---------|----------|--------|
| コンテナポート | 8000（実装方針の`CMD`で指定） | - | ⚠️ Dockerfileで`EXPOSE 8000`を追記推奨 |
| ALBターゲット | - | ALB → ECS Task:8080 | ❓ ポート番号の不一致可能性 |
| ヘルスチェック | `/{tenant_id}/health` | ALB ヘルスチェック | ✅ エンドポイント整合 |

**改善提案**:
1. **Dockerfileでポートを明示**
   - 実装方針（06_実装方針.md）のDockerfileに、`EXPOSE 8000` を追加してください。
   ```dockerfile
   FROM python:3.10-slim
   WORKDIR /app
   COPY requirements.txt .
   RUN pip install --no-cache-dir -r requirements.txt
   COPY src/ ./src/
   ENV PYTHONUNBUFFERED=1
   ENV DD_SERVICE=demo-api
   ENV DD_ENV=poc
   EXPOSE 8000  # ← 追加
   HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
     CMD curl -f http://localhost:8000/tenant-a/health || exit 1
   CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8000"]
   ```

2. **ALBターゲットポートとの整合確認**
   - インフラ設計のALB設定で、ECS Taskのターゲットポートが8000か8080か確認してください。
   - アプリ側はDockerfileで8000を使用していますが、ALBターゲットグループのポートと一致させる必要があります。

**理由**: コンテナポートとALBターゲットポートの不一致は、アプリケーションが起動しない原因となります。

---

### ✅ 環境変数設計（実装方針、セキュリティ設計）

**評価**: 適切

| 環境変数 | App設計 | Infra設計 | 整合性 |
|---------|---------|----------|--------|
| DATABASE_URL | 環境変数で管理 | ECS Task Definition で注入 | ✅ 一致 |
| DD_API_KEY | 環境変数で管理 | ECS Task Definition で注入 | ✅ 一致 |
| DD_SERVICE | demo-api | - | ✅ 適切 |
| DD_ENV | poc | - | ✅ 適切 |
| VALID_TENANTS | tenant-a,tenant-b,tenant-c | - | ✅ 適切 |

**コメント**: 環境変数の設計は適切です。インフラ側のECS Task Definitionで環境変数を注入する方針と整合しています。

---

### ✅ Datadog Agent 統合（インフラストラクチャ層）

**評価**: 適切（ddtrace設定の詳細化推奨）

| 項目 | App設計 | Infra設計 | 整合性 |
|------|---------|----------|--------|
| ddtrace 統合 | datadog_middleware.py で実装 | Datadog Agent（ECS Task内） | ✅ 整合 |
| トレース送信先 | Datadog APM | Datadog SaaS | ✅ 整合 |
| カスタムタグ | tenant_id をタグ付与 | - | ✅ L3テナント監視で活用可能 |

**改善提案**:
1. **datadog_middleware.pyの詳細化**
   - コンポーネント設計（02_コンポーネント設計.md）の`datadog_middleware.py`の説明を詳細化してください。
   - 具体的には、以下の実装例を追記推奨:
   ```python
   # datadog_middleware.py の実装例（コンポーネント設計に追記）
   from ddtrace import patch_all, tracer
   from fastapi import Request

   # ddtrace 初期化（FastAPI全体にトレースを統合）
   patch_all()

   # カスタムタグ設定ミドルウェア
   async def add_tenant_tag(request: Request, call_next):
       # パスパラメータから tenant_id を取得
       tenant_id = request.path_params.get('tenant_id')
       if tenant_id:
           # Datadog トレースにタグ追加
           tracer.current_span().set_tag('tenant_id', tenant_id)
       response = await call_next(request)
       return response
   ```

**理由**: L3テナント監視（FR-003）では、Datadog APMトレースの`tenant_id`タグを使用してテナント別の監視を実現します。この実装が適切に行われることが重要です。

---

## 3. ALB構成との整合性

### ✅ ヘルスチェックエンドポイント（API設計）

**評価**: 適切

| 項目 | App設計 | Infra設計 | 整合性 |
|------|---------|----------|--------|
| エンドポイント | `GET /{tenant_id}/health` | ALB ヘルスチェック | ✅ 整合 |
| レスポンス | 200 OK（正常時） | - | ✅ 適切 |
| レスポンス | 503 Service Unavailable（DB接続失敗時） | - | ✅ 適切 |

**コメント**:
- ヘルスチェックエンドポイントは適切に設計されています。
- ALB側のヘルスチェック設定で、パス`/tenant-a/health`を指定すれば整合します。

---

### ✅ パスベースルーティング

**評価**: 不要（マルチテナントはアプリ側で実現）

| 項目 | App設計 | Infra設計 | 整合性 |
|------|---------|----------|--------|
| テナント分離方法 | パスパラメータ `/{tenant_id}/...` | - | ✅ ALB側のパスルーティング不要 |

**コメント**:
- マルチテナントはアプリケーション層で実現（`tenant_id`をパスパラメータで受け取る）しています。
- ALB側でパスベースルーティング（例: `/tenant-a` → ターゲットグループA）は不要です。
- ALBは単一のターゲットグループ（ECS Service）にルーティングすればOKです。

---

## 4. Datadog監視との整合性

### ✅ L0監視（RDS）

**評価**: 適切

| 項目 | App設計 | Infra設計 | 整合性 |
|------|---------|----------|--------|
| RDS接続 | items テーブルへのCRUD操作 | L0 RDS Monitor（CPU、接続数、メモリ、ストレージ） | ✅ 監視データ生成 |

**コメント**: アプリケーションのRDSアクセスが、L0監視のメトリクス（CPU使用率、接続数等）を生成します。適切です。

---

### ✅ L2監視（ECS Task）

**評価**: 適切

| 項目 | App設計 | Infra設計 | 整合性 |
|------|---------|----------|--------|
| ECS Task停止 | `POST /admin/shutdown` で `os._exit(0)` | L2 ECS Task Monitor（タスク状態） | ✅ 異常停止検知可能 |

**コメント**: `/admin/shutdown`エンドポイントでECS Taskを停止させる設計は、L2監視の検証に有効です。

---

### ⚠️ L3監視（テナント別）

**評価**: 適切（ddtrace設定の詳細化推奨）

| 項目 | App設計 | Infra設計 | 整合性 |
|------|---------|----------|--------|
| ヘルスチェック | `GET /{tenant_id}/health` | L3 Health Monitor（tenant-a/b/c） | ✅ 整合 |
| エラーログ | `POST /{tenant_id}/simulate/error` | L3 Error Log Monitor | ✅ 整合 |
| レイテンシ | `POST /{tenant_id}/simulate/latency` | L3 Latency Monitor（p99） | ✅ 整合 |
| Datadog APMタグ | tenant_id をカスタムタグ | Datadog Monitorでタグフィルタリング | ⚠️ 実装詳細化推奨 |

**改善提案**:
- **datadog_middleware.pyの実装詳細を明記**（前述の「2. ECS構成との整合性」を参照）
- **API設計書（04_API設計.md）のトレース例に、tenant_idタグを追加**
  ```json
  {
    "service": "demo-api",
    "env": "poc",
    "version": "1.0.0",
    "resource": "GET /{tenant_id}/items",
    "tags": {
      "tenant_id": "tenant-a",  // ← L3監視で使用
      "http.method": "GET",
      "http.status_code": 200,
      "http.url": "/tenant-a/items"
    },
    "duration": 45
  }
  ```

**理由**: インフラ側のL3監視（Datadog Monitor）は、APMトレースの`tenant_id`タグを使用してテナント別アラートを実現します。

---

## 5. セキュリティ設計との整合性

### ✅ テナント分離（セキュリティ設計）

**評価**: 適切

| 項目 | App設計 | Infra設計 | 整合性 |
|------|---------|----------|--------|
| テナント検証 | tenant_service.py で検証 | - | ✅ 適切 |
| Row-Level Security | WHERE句に `tenant_id = ?` | - | ✅ 適切 |
| 有効なテナント | tenant-a, tenant-b, tenant-c | L3 Monitor（3テナント） | ✅ 一致 |

**コメント**: テナント分離は適切に設計されています。

---

### ⚠️ シークレット管理（セキュリティ設計）

**評価**: 適切（RDS接続時のSSL/TLS設定を明記推奨）

| 項目 | App設計 | Infra設計 | 整合性 |
|------|---------|----------|--------|
| RDS パスワード | 環境変数 `DATABASE_URL` | ECS Task Definition で注入 | ✅ 一致 |
| Datadog API Key | 環境変数 `DD_API_KEY` | ECS Task Definition で注入 | ✅ 一致 |
| ハードコード禁止 | .gitignore 設定済み | - | ✅ 適切 |
| 本番移行時 | Secrets Manager 推奨 | Secrets Manager 推奨 | ✅ 一致 |

**改善提案**:
- **RDS接続文字列のSSL/TLS設定を明記**（前述の「1. RDS構成との整合性」を参照）

---

### ✅ SQLインジェクション対策（セキュリティ設計）

**評価**: 適切

| 項目 | App設計 | Infra設計 | 整合性 |
|------|---------|----------|--------|
| パラメータ化クエリ | SQLAlchemy ORM使用 | - | ✅ 適切 |
| 生SQL禁止 | セキュリティ設計に明記 | - | ✅ 適切 |

**コメント**: SQLインジェクション対策は適切です。

---

### ✅ エラーハンドリング（セキュリティ設計）

**評価**: 適切

| 項目 | App設計 | Infra設計 | 整合性 |
|------|---------|----------|--------|
| スタックトレース非公開 | error_handler.py で実装 | - | ✅ 適切 |
| 統一エラーレスポンス | JSON形式 | - | ✅ 適切 |

**コメント**: エラーハンドリングは適切に設計されています。

---

## 📝 改善提案サマリー

| 優先度 | 対象ファイル | 指摘内容 | 推奨対応 |
|-------|------------|---------|---------|
| **高** | 06_実装方針.md | Dockerfileで`EXPOSE 8000`を明記 | Dockerfile に `EXPOSE 8000` を追加 |
| **中** | 05_セキュリティ設計.md | RDS接続時のSSL/TLS設定を明記 | `DATABASE_URL` に `sslmode=require` を追記 |
| **中** | 02_コンポーネント設計.md | datadog_middleware.py の実装詳細を明記 | `tenant_id`タグ設定の実装例を追記 |

---

## ✅ 承認条件

以下の条件を満たせば、**承認**します:

1. **必須対応**:
   - 06_実装方針.md の Dockerfile に `EXPOSE 8000` を追加
   - ALBターゲットポートとの整合確認（8000 or 8080）

2. **推奨対応**（本番移行時に実施でも可）:
   - RDS接続時のSSL/TLS設定を明記
   - datadog_middleware.py の実装詳細を明記

---

## 📊 総合評価（再掲）

**✅ 条件付き承認**

- アプリケーション設計は全体として適切であり、インフラ設計との整合性も高い。
- 上記の改善提案（特に優先度「高」の項目）を対応すれば、実装フェーズに進んで問題ありません。

---

## 📝 レビュー後のアクション

1. **App-Architect**: 上記の改善提案を検討し、必要に応じて設計書を更新
2. **PM**: App-Architect の修正完了後、ユーザーに提示・承認を得る
3. **Coder**: 設計書承認後、実装フェーズに進む

---

**作成日**: 2025-12-28
**レビュアー**: Infra-Architect
**ステータス**: 完了（条件付き承認）
