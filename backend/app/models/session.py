"""AccessSession SQLAlchemy model for remote access requests & active sessions."""

import uuid
from datetime import datetime, timezone, timedelta

from sqlalchemy import Boolean, Column, DateTime, ForeignKey, String
from sqlalchemy.orm import relationship

from app.database import Base


def _utcnow():
    return datetime.now(timezone.utc).replace(tzinfo=None)


class AccessSession(Base):
    __tablename__ = "access_sessions"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))

    requester_device_id = Column(
        String(8),
        ForeignKey("devices.device_id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    target_device_id = Column(
        String(8),
        ForeignKey("devices.device_id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    # Status lifecycle: pending -> active | rejected | expired | ended
    status = Column(String(16), nullable=False, default="pending", index=True)

    # Permission flags granted by target device
    view_only = Column(Boolean, default=False, nullable=False)
    can_control = Column(Boolean, default=False, nullable=False)

    # Session token issued upon explicit approval
    session_token = Column(String(64), nullable=True, unique=True, index=True)

    created_at = Column(DateTime, default=_utcnow, nullable=False)
    expires_at = Column(DateTime, nullable=False) # pending timeout (e.g. 60s)
    accepted_at = Column(DateTime, nullable=True)
    ended_at = Column(DateTime, nullable=True)

    requester = relationship(
        "Device",
        foreign_keys=[requester_device_id],
        primaryjoin="AccessSession.requester_device_id == Device.device_id",
    )
    target = relationship(
        "Device",
        foreign_keys=[target_device_id],
        primaryjoin="AccessSession.target_device_id == Device.device_id",
    )

    def is_expired(self) -> bool:
        if self.status == "pending" and self.expires_at:
            exp = self.expires_at
            if exp.tzinfo is not None:
                exp = exp.astimezone(timezone.utc).replace(tzinfo=None)
            return _utcnow() > exp
        return False

    def __repr__(self) -> str:
        return (
            f"<AccessSession {self.requester_device_id}->{self.target_device_id} "
            f"status={self.status!r} control={self.can_control}>"
        )
