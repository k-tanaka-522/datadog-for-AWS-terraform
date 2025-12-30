FROM python:3.10-slim

# 作業ディレクトリ設定
WORKDIR /app

# システム依存関係インストール（curlはヘルスチェック用）
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

# 依存関係インストール
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# アプリケーションコードコピー
COPY src/ ./src/

# 環境変数設定（デフォルト値）
ENV PYTHONUNBUFFERED=1
ENV PYTHONPATH=/app/src
ENV DD_SERVICE=demo-api
ENV DD_ENV=poc

# ポート公開（ALB ターゲットグループから 8080 番ポートでアクセス）
EXPOSE 8080

# ヘルスチェック
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8080/health || exit 1

# アプリケーション起動
CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8080"]
