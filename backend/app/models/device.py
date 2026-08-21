"""Device SQLAlchemy model."""

import uuid
from datetime import datetime, timezone

from sqlalchemy import Boolean, Column, DateTime, ForeignKey, String
from sqlalchemy.orm import relationship

from app.database import Base


def _utcnow():
    return datetime.now(timezone.utc)


class Device(Base):
    __tablename__ = "devices"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(String(36), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)

    # 8-digit numeric string — unique across all installations
    device_id = Column(String(8), unique=True, nullable=False, index=True)
    device_name = Column(String(128), nullable=False, default="My Device")
    platform = Column(String(32), nullable=False, default="android")
    app_version = Column(String(32), nullable=True)

    # FCM token for push notifications (Phase 3)
    fcm_token = Column(String(512), nullable=True)

    # Presence tracking
    online = Column(Boolean, default=False, nullable=False)
    last_seen = Column(DateTime(timezone=True), nullable=True)

    created_at = Column(DateTime(timezone=True), default=_utcnow, nullable=False)
    updated_at = Column(DateTime(timezone=True), default=_utcnow, onupdate=_utcnow, nullable=False)

    # Relationships
    user = relationship("User", back_populates="devices")

    def __repr__(self) -> str:
        return f"<Device device_id={self.device_id!r} name={self.device_name!r} online={self.online}>"
