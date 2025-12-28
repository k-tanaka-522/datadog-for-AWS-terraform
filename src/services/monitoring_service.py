"""
監視データ生成サービス

目的: エラー/遅延シミュレーション、Datadog監視データ生成
影響範囲: simulate_controller.py
前提条件: logger.py（構造化ログ出力）
"""

import time
import random
from typing import Dict, Any
from infrastructure.logger import get_logger

logger = get_logger()


class MonitoringService:
    """
    監視データ生成サービス

    責務:
        - エラーシミュレーション（500エラー発生）
        - レイテンシシミュレーション（遅延発生）
        - 監視データ生成（ログ、メトリクス）

    影響範囲:
        - simulate_controller.py（シミュレーションエンドポイント）

    前提条件:
        - logger.py で構造化ログが出力される
    """

    @staticmethod
    def simulate_error(tenant_id: str, error_type: str = "generic") -> None:
        """
        エラーをシミュレーション（例外を発生）

        目的:
            - Datadog エラートラッキングテスト
            - アラート設定テスト

        影響範囲:
            - simulate_controller.py（POST /{tenant_id}/simulate/error）

        Args:
            tenant_id (str): テナントID
            error_type (str): エラー種別（generic, database, external_api）

        Raises:
            Exception: 常に例外を発生（エラーシミュレーション）

        監視項目:
            - Datadog Error Tracking
            - ログ（severity: error, error_type: simulation_error）
        """
        error_messages = {
            "generic": f"Simulated generic error for tenant {tenant_id}",
            "database": f"Simulated database error for tenant {tenant_id}",
            "external_api": f"Simulated external API error for tenant {tenant_id}",
        }

        error_message = error_messages.get(error_type, error_messages["generic"])

        # 構造化ログ出力
        logger.error(
            f"Simulating error: {error_message}",
            extra={
                "tenant_id": tenant_id,
                "error_type": error_type,
                "simulation": True,
                "severity": "error"
            }
        )

        raise Exception(error_message)

    @staticmethod
    def simulate_latency(tenant_id: str, duration_ms: int = 1000) -> Dict[str, Any]:
        """
        レイテンシをシミュレーション（指定時間スリープ）

        目的:
            - Datadog APM レイテンシトラッキングテスト
            - パフォーマンス監視テスト

        影響範囲:
            - simulate_controller.py（POST /{tenant_id}/simulate/latency）

        Args:
            tenant_id (str): テナントID
            duration_ms (int): 遅延時間（ミリ秒）デフォルト 1000ms

        Returns:
            Dict[str, Any]: {
                "tenant_id": str,
                "latency_ms": int,
                "message": str
            }

        監視項目:
            - Datadog APM（レスポンスタイム）
            - ログ（severity: info, latency_ms: int）
        """
        # 構造化ログ出力
        logger.info(
            f"Simulating latency: {duration_ms}ms for tenant {tenant_id}",
            extra={
                "tenant_id": tenant_id,
                "latency_ms": duration_ms,
                "simulation": True
            }
        )

        # 指定時間スリープ
        time.sleep(duration_ms / 1000.0)

        return {
            "tenant_id": tenant_id,
            "latency_ms": duration_ms,
            "message": f"Simulated latency of {duration_ms}ms for tenant {tenant_id}"
        }

    @staticmethod
    def generate_random_metric(tenant_id: str) -> Dict[str, Any]:
        """
        ランダムメトリクスを生成（監視データ生成）

        目的:
            - Datadog カスタムメトリクス送信テスト
            - ダッシュボード表示テスト

        Args:
            tenant_id (str): テナントID

        Returns:
            Dict[str, Any]: {
                "tenant_id": str,
                "metric_name": str,
                "metric_value": float,
                "timestamp": float
            }
        """
        metric_value = random.uniform(0, 100)

        return {
            "tenant_id": tenant_id,
            "metric_name": "demo.random_metric",
            "metric_value": metric_value,
            "timestamp": time.time()
        }
