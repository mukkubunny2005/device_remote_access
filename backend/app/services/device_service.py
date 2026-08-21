"""Device business logic service."""

import random
import string
from datetime import datetime, timezone
from typing import Optional

from sqlalchemy.orm import Session

from app.models.device import Device
from app.schemas.device import DeviceRegisterRequest


# ── ID Generation ──────────────────────────────────────────────────────────────

def _random_8_digit() -> str:
    """Return a cryptographically random 8-digit string (00000000–99999999).
    Uses secrets-quality randomness via SystemRandom."""
    rng = random.SystemRandom()
    return "".join(rng.choices(string.digits, k=8))


def generate_unique_device_id(db: Session, max_attempts: int = 10) -> str:
    """Generate a unique 8-digit Device ID not already present in the database."""
    for _ in range(max_attempts):
        candidate = _random_8_digit()
        exists = db.query(Device).filter(Device.device_id == candidate).first()
        if not exists:
            return candidate
    raise RuntimeError("Could not generate a unique Device ID after maximum attempts.")


# ── CRUD ───────────────────────────────────────────────────────────────────────

def register_device(
    db: Session,
    user_id: str,
    payload: DeviceRegisterRequest,
) -> Device:
    """Register or update a device for the given user.

    If the device_id already exists and belongs to this user, update it.
    If it exists but belongs to another user, raise ValueError.
    """
    existing = db.query(Device).filter(Device.device_id == payload.device_id).first()

    if existing:
        if existing.user_id != user_id:
            raise ValueError("Device ID already registered to another account.")
        # Update existing record (e.g. device name or app version changed)
        existing.device_name = payload.device_name
        existing.platform = payload.platform
        existing.app_version = payload.app_version
        existing.online = True
        existing.last_seen = datetime.now(timezone.utc)
        db.commit()
        db.refresh(existing)
        return existing

    device = Device(
        user_id=user_id,
        device_id=payload.device_id,
        device_name=payload.device_name,
        platform=payload.platform,
        app_version=payload.app_version,
        online=True,
        last_seen=datetime.now(timezone.utc),
    )
    db.add(device)
    db.commit()
    db.refresh(device)
    return device


def get_device_by_device_id(db: Session, device_id: str) -> Optional[Device]:
    return db.query(Device).filter(Device.device_id == device_id).first()


def get_devices_by_user(db: Session, user_id: str) -> list[Device]:
    return db.query(Device).filter(Device.user_id == user_id).all()


def update_device_status(db: Session, device_id: str, online: bool) -> Optional[Device]:
    device = get_device_by_device_id(db, device_id)
    if device:
        device.online = online
        device.last_seen = datetime.now(timezone.utc)
        db.commit()
        db.refresh(device)
    return device


def update_fcm_token(db: Session, device_id: str, fcm_token: str) -> Optional[Device]:
    device = get_device_by_device_id(db, device_id)
    if device:
        device.fcm_token = fcm_token
        db.commit()
        db.refresh(device)
    return device
