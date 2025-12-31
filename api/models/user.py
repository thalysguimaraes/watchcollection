from sqlalchemy import Column, String, DateTime
from sqlalchemy.dialects.sqlite import JSON
from datetime import datetime
import uuid

from database import Base


def generate_uuid() -> str:
    return str(uuid.uuid4())


class User(Base):
    __tablename__ = "user"

    id = Column(String, primary_key=True, default=generate_uuid)
    email = Column(String, unique=True, nullable=False, index=True)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    entitlement = Column(String, default="free", nullable=False)
    apple_user_id = Column(String, unique=True, nullable=True)
    last_login_at = Column(DateTime, nullable=True)
