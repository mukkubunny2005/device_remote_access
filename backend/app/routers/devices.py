"""Device router.

Endpoints:
    POST  /devices/register          — register / re-register a device
    GET   /devices/me                — list the caller's devices
    GET   /devices/{device_id}       — look up a device by its 8-digit ID
    PATCH /devices/{device_id}/status — heartbeat / mark online or offline
    POST  /devices/fcm-token         — store FCM token (Phase 3 ready)
"""

import logging
from typing import List

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.user import User
from app.schemas.device import (
    DeviceFCMTokenUpdate,
    DeviceLookupOut,
    DeviceOut,
    DeviceRegisterRequest,
    DeviceStatusUpdate,
)
from app.security.jwt import get_current_user
from app.services import device_service

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/devices", tags=["Devices"])


@router.post("/register", response_model=DeviceOut, status_code=status.HTTP_201_CREATED)
def register_device(
    payload: DeviceRegisterRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Register (or update) a device for the authenticated user.

    The mobile app calls this on first launch with the locally-generated
    8-digit Device ID. If the ID already belongs to this user, the record
    is updated (e.g. after an app version change).
    """
    try:
        device = device_service.register_device(db, current_user.id, payload)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc))

    logger.info("Device registered: %s for user %s", device.device_id, current_user.id)
    return device


@router.get("/me", response_model=List[DeviceOut])
def my_devices(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Return all devices registered to the authenticated user."""
    return device_service.get_devices_by_user(db, current_user.id)


@router.get("/{device_id}", response_model=DeviceLookupOut)
def lookup_device(
    device_id: str,
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),  # must be authenticated
):
    """Look up minimal public info for any device by its 8-digit ID.

    Used by the pairing flow (Phase 2): Device A looks up Device B before
    sending a pairing request.
    """
    device = device_service.get_device_by_device_id(db, device_id)
    if not device:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Device '{device_id}' not found.",
        )
    return device


@router.patch("/{device_id}/status", response_model=DeviceOut)
def update_status(
    device_id: str,
    payload: DeviceStatusUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Heartbeat / presence endpoint.

    The mobile app calls this periodically (or on connect/disconnect)
    to update the online/offline status. Only the owning user may update.
    """
    device = device_service.get_device_by_device_id(db, device_id)
    if not device:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Device not found.")
    if device.user_id != current_user.id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not your device.")

    updated = device_service.update_device_status(db, device_id, payload.online)
    return updated


@router.post("/fcm-token", status_code=status.HTTP_204_NO_CONTENT)
def update_fcm_token(
    payload: DeviceFCMTokenUpdate,
    device_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Store the FCM registration token for this device. (Phase 3 ready)"""
    device = device_service.get_device_by_device_id(db, device_id)
    if not device or device.user_id != current_user.id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Device not found.")
    device_service.update_fcm_token(db, device_id, payload.fcm_token)
    return
