"""Pydantic schemas for device endpoints."""

import re
from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field, field_validator


DEVICE_ID_RE = re.compile(r"^\d{8}$")


class DeviceRegisterRequest(BaseModel):
    device_id: str = Field(description="Exactly 8 numeric digits")
    device_name: str = Field(min_length=1, max_length=128, default="My Device")
    platform: str = Field(default="android", max_length=32)
    app_version: Optional[str] = Field(default=None, max_length=32)

    @field_validator("device_id")
    @classmethod
    def validate_device_id(cls, v: str) -> str:
        if not DEVICE_ID_RE.match(v):
            raise ValueError("device_id must be exactly 8 numeric digits")
        return v


class DeviceOut(BaseModel):
    id: str
    device_id: str
    device_name: str
    platform: str
    app_version: Optional[str]
    online: bool
    last_seen: Optional[datetime]
    created_at: datetime

    model_config = {"from_attributes": True}


class DeviceStatusUpdate(BaseModel):
    online: bool


class DeviceFCMTokenUpdate(BaseModel):
    fcm_token: str = Field(max_length=512)


class DeviceLookupOut(BaseModel):
    """Minimal public info returned when looking up another device by ID."""
    device_id: str
    device_name: str
    online: bool

    model_config = {"from_attributes": True}
