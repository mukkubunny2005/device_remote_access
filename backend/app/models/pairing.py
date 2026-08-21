"""Pairing SQLAlchemy model."""

import uuid
from datetime import datetime, timezone

from sqlalchemy import Column, DateTime, ForeignKey, String
from sqlalchemy.orm import relationship

from app.database import Base


def _utcnow():
    return datetime.now(timezone.utc)


class Pairing(Base):
    __tablename__ = "pairings"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))

    # 8-digit device IDs (not FK to devices.id — FK to devices.device_id)
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

    # Status lifecycle: pending → accepted | rejected | revoked
    status = Column(String(16), nullable=False, default="pending", index=True)

    created_at  = Column(DateTime(timezone=True), default=_utcnow, nullable=False)
    accepted_at = Column(DateTime(timezone=True), nullable=True)
    revoked_at  = Column(DateTime(timezone=True), nullable=True)

    # Relationships
    requester = relationship("Device", foreign_keys=[requester_device_id],
                             primaryjoin="Pairing.requester_device_id == Device.device_id")
    target    = relationship("Device", foreign_keys=[target_device_id],
                             primaryjoin="Pairing.target_device_id == Device.device_id")

    def __repr__(self) -> str:
        return (
            f"<Pairing {self.requester_device_id}→{self.target_device_id} "
            f"status={self.status!r}>"
        )
