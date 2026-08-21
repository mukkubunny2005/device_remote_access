"""Pydantic schemas for pairing endpoints."""

from datetime import datetime
from typing import Literal, Optional

from pydantic import BaseModel


PairingStatus = Literal["pending", "accepted", "rejected", "revoked"]


class PairingRequestCreate(BaseModel):
    target_device_id: str


class PairingOut(BaseModel):
    id: str
    requester_device_id: str
    target_device_id: str
    status: str
    created_at: datetime
    accepted_at: Optional[datetime] = None
    revoked_at: Optional[datetime] = None

    model_config = {"from_attributes": True}


class PairingRespondRequest(BaseModel):
    """Body sent by Device B when accepting or rejecting a pairing."""
    action: Literal["accept", "reject"]


class PairingRevokeRequest(BaseModel):
    """Body to revoke an accepted pairing."""
    pass  # No body needed — device_id comes from JWT + path param
