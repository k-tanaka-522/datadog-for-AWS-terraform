"""
横断的関心事パッケージ

このパッケージはログ、エラーハンドリング、Datadog統合を提供します。
"""

from .logger import setup_logger, get_logger
from .error_handler import register_error_handlers
from .datadog_middleware import setup_datadog

__all__ = [
    "setup_logger",
    "get_logger",
    "register_error_handlers",
    "setup_datadog",
]
