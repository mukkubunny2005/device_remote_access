"""Pydantic schemas for remote access session endpoints."""

from datetime import datetime
from typing import Literal, Optional
from pydantic import BaseModel

AccessStatus = Literal["pending", "active", "rejected", "expired", "ended"]


class AccessRequestCreate(BaseModel):
    target_device_id: str
    request_control: bool = True


class AccessRespondRequest(BaseModel):
    action: Literal["accept", "reject"]
    allow_control: bool = True


class AccessSessionOut(BaseModel):
    id: str
    requester_device_id: str
    target_device_id: str
    status: str
    view_only: bool
    can_control: bool
    session_token: Optional[str] = None
    created_at: datetime
    expires_at: datetime
    accepted_at: Optional[datetime] = None
    ended_at: Optional[datetime] = None

    model_config = {"from_attributes": True}
