import logging
import sys
from pythonjsonlogger import jsonlogger

_logger = None


def setup_logging() -> logging.Logger:
    global _logger
    if _logger is not None:
        return _logger

    logger = logging.getLogger("api")
    logger.setLevel(logging.INFO)

    if not logger.handlers:
        handler = logging.StreamHandler(sys.stdout)
        formatter = jsonlogger.JsonFormatter(
            "%(asctime)s %(levelname)s %(name)s %(message)s",
            timestamp=True,
        )
        handler.setFormatter(formatter)
        logger.addHandler(handler)

    _logger = logger
    return logger


def get_logger() -> logging.Logger:
    global _logger
    if _logger is None:
        return setup_logging()
    return _logger
