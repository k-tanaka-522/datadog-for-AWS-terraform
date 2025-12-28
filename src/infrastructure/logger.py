"""
構造化ログ出力

目的: JSON形式ログ出力、Datadog APM連携、トレースID自動付与
影響範囲: すべてのモジュール
前提条件: LOG_LEVEL環境変数が設定されている
"""

import logging
import json
import sys
from datetime import datetime
from typing import Any, Dict
from ddtrace import tracer
from config.settings import settings


class JSONFormatter(logging.Formatter):
    """
    JSON形式のログフォーマッター

    責務:
        - ログレコードをJSON形式に変換
        - Datadog APM トレースID、スパンIDを自動付与
        - ISO 8601形式のタイムスタンプ

    影響範囲:
        - すべてのログ出力

    前提条件:
        - ddtrace が初期化されている
    """

    def format(self, record: logging.LogRecord) -> str:
        """
        ログレコードをJSON形式に変換

        Args:
            record (logging.LogRecord): ログレコード

        Returns:
            str: JSON形式のログ文字列

        出力例:
            {
                "timestamp": "2025-12-28T10:00:00Z",
                "level": "INFO",
                "message": "Request received",
                "dd.trace_id": "abc123",
                "dd.span_id": "def456",
                "tenant_id": "tenant-a"
            }
        """
        # 基本フィールド
        log_data: Dict[str, Any] = {
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "level": record.levelname,
            "message": record.getMessage(),
            "module": record.module,
            "function": record.funcName,
            "line": record.lineno,
            "service": settings.DD_SERVICE,
            "env": settings.DD_ENV,
        }

        # Datadog APM トレースID、スパンID を付与
        span = tracer.current_span()
        if span:
            log_data["dd.trace_id"] = span.trace_id
            log_data["dd.span_id"] = span.span_id

        # カスタムフィールド（extra で渡された情報）
        if hasattr(record, 'tenant_id'):
            log_data['tenant_id'] = record.tenant_id

        if hasattr(record, 'error_type'):
            log_data['error_type'] = record.error_type

        if hasattr(record, 'severity'):
            log_data['severity'] = record.severity

        if hasattr(record, 'health_check_level'):
            log_data['health_check_level'] = record.health_check_level

        if hasattr(record, 'health_check_type'):
            log_data['health_check_type'] = record.health_check_type

        # エラーログの場合、status="error", tenant="tenant_id" を追加
        if record.levelname == 'ERROR':
            log_data['status'] = 'error'
            if hasattr(record, 'tenant_id'):
                log_data['tenant'] = record.tenant_id

        # 例外情報を追加
        if record.exc_info:
            log_data['exception'] = self.formatException(record.exc_info)

        return json.dumps(log_data, ensure_ascii=False)


def setup_logger(name: str = "demo-api") -> logging.Logger:
    """
    構造化ログを出力するロガーをセットアップ

    目的:
        - JSON形式の構造化ログ出力
        - Datadog APM トレースID自動付与
        - 環境変数によるログレベル制御

    影響範囲:
        - すべてのモジュールで使用

    前提条件:
        - LOG_LEVEL 環境変数が設定されている（デフォルト: INFO）

    Args:
        name (str): ロガー名（デフォルト: "demo-api"）

    Returns:
        logging.Logger: 設定済みロガー
    """
    logger = logging.getLogger(name)
    logger.setLevel(getattr(logging, settings.LOG_LEVEL))

    # 既存のハンドラをクリア（重複防止）
    logger.handlers.clear()

    # ハンドラ設定（標準出力）
    handler = logging.StreamHandler(sys.stdout)
    handler.setLevel(getattr(logging, settings.LOG_LEVEL))

    # フォーマッター設定（JSON形式）
    formatter = JSONFormatter()
    handler.setFormatter(formatter)

    logger.addHandler(handler)

    # ログの伝播を無効化（ルートロガーと重複しないようにする）
    logger.propagate = False

    return logger


# グローバルロガーインスタンス
_logger = None


def get_logger() -> logging.Logger:
    """
    グローバルロガーを取得（シングルトン）

    Returns:
        logging.Logger: 設定済みロガー
    """
    global _logger
    if _logger is None:
        _logger = setup_logger()
    return _logger
