from sqlalchemy import Column, Integer, String, DateTime, ForeignKey
from datetime import datetime

from database import Base


class UsageLog(Base):
    __tablename__ = "usage_log"

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(String, ForeignKey("user.id"), nullable=False, index=True)
    endpoint = Column(String, nullable=False)
    watch_id = Column(String, nullable=True)
    tokens_used = Column(Integer, nullable=False)
    provider = Column(String, nullable=False)
    latency_ms = Column(Integer, nullable=False)
    status = Column(String, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False, index=True)
