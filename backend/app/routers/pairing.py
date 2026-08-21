"""Pairing router.

Endpoints:
    POST   /pairing/request              — Device A requests to pair with Device B
    POST   /pairing/{id}/respond         — Device B accepts or rejects
    DELETE /pairing/{id}                 — Either device revokes the pairing
    GET    /pairing/pending              — Incoming pending requests for my devices
    GET    /pairing/paired               — All accepted pairings for my devices
    GET    /pairing/all                  — All pairings (any status) for my devices
"""

import asyncio
import json
import logging
from typing import List

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.database import get_db, SessionLocal
from app.models.device import Device
from app.models.user import User
from app.schemas.pairing import PairingOut, PairingRequestCreate, PairingRespondRequest
from app.security.jwt import get_current_user
from app.services import pairing_service
from app.services.device_service import get_devices_by_user
from app.websocket.manager import manager

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/pairing", tags=["Pairing"])


# ── Helpers ────────────────────────────────────────────────────────────────────

def _get_user_device_ids(db: Session, user: User) -> List[str]:
    """Return all device_ids owned by the authenticated user."""
    return [d.device_id for d in get_devices_by_user(db, user.id)]


def _assert_owns_device(device_id: str, user_device_ids: List[str]) -> None:
    if device_id not in user_device_ids:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You do not own this device.",
        )


async def _notify_device(device_id: str, payload: dict) -> None:
    """Best-effort WebSocket notification — never raises."""
    try:
        await manager.send_to_device(device_id, payload)
    except Exception as exc:
        logger.debug("WS notify failed for %s: %s", device_id, exc)


# ── Endpoints ──────────────────────────────────────────────────────────────────

@router.post("/request", response_model=PairingOut, status_code=status.HTTP_201_CREATED)
async def request_pairing(
    payload: PairingRequestCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Device A sends a pairing request to Device B.

    - requester_device_id is inferred from the caller's devices.
    - A user may only send from a device they own.
    - Notifies Device B via WebSocket if it is currently connected.
    """
    my_device_ids = _get_user_device_ids(db, current_user)
    if not my_device_ids:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="You have no registered devices. Register a device first.",
        )

    # Use the first (or only) device that is NOT the target
    requester_device_id = next(
        (did for did in my_device_ids if did != payload.target_device_id),
        None,
    )
    if requester_device_id is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot pair a device with itself.",
        )

    try:
        pairing = pairing_service.send_pairing_request(
            db, requester_device_id, payload.target_device_id
        )
    except LookupError as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(e))
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(e))

    # Real-time notification to target device if online
    await _notify_device(
        payload.target_device_id,
        {
            "type": "pairing_request",
            "pairing_id": pairing.id,
            "requester_device_id": requester_device_id,
            "message": f"Device {requester_device_id} wants to pair with you.",
        },
    )

    return pairing


@router.post("/{pairing_id}/respond", response_model=PairingOut)
async def respond_pairing(
    pairing_id: str,
    payload: PairingRespondRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Device B explicitly accepts or rejects a pending pairing request.
    Only the target device may respond.
    """
    my_device_ids = _get_user_device_ids(db, current_user)

    try:
        # Find a device owned by the current user that matches the pairing target
        pairing_record = pairing_service.get_pairing_by_id(db, pairing_id)
        if not pairing_record:
            raise LookupError("Pairing request not found.")
        if pairing_record.target_device_id not in my_device_ids:
            raise PermissionError("Only the target device's owner may respond.")

        pairing = pairing_service.respond_to_pairing(
            db, pairing_id, pairing_record.target_device_id, payload.action
        )
    except LookupError as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(e))
    except PermissionError as e:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=str(e))
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))

    # Notify the requester of the decision
    await _notify_device(
        pairing.requester_device_id,
        {
            "type": "pairing_response",
            "pairing_id": pairing.id,
            "status": pairing.status,
            "target_device_id": pairing.target_device_id,
            "message": (
                f"Device {pairing.target_device_id} "
                f"{'accepted' if pairing.status == 'accepted' else 'rejected'} your pairing request."
            ),
        },
    )

    return pairing


@router.delete("/{pairing_id}", response_model=PairingOut)
async def revoke_pairing(
    pairing_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Either participant can revoke (cancel or remove) a pairing at any time.
    """
    my_device_ids = _get_user_device_ids(db, current_user)
    pairing_record = pairing_service.get_pairing_by_id(db, pairing_id)
    if not pairing_record:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Pairing not found.")

    # Determine which of the caller's devices is in this pairing
    actor_device_id = next(
        (did for did in my_device_ids
         if did in (pairing_record.requester_device_id, pairing_record.target_device_id)),
        None,
    )
    if not actor_device_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN,
                            detail="You are not a participant in this pairing.")

    try:
        pairing = pairing_service.revoke_pairing(db, pairing_id, actor_device_id)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))

    # Notify the other device
    other_device_id = (
        pairing.target_device_id
        if actor_device_id == pairing.requester_device_id
        else pairing.requester_device_id
    )
    await _notify_device(
        other_device_id,
        {
            "type": "pairing_revoked",
            "pairing_id": pairing.id,
            "by_device_id": actor_device_id,
            "message": f"Device {actor_device_id} removed the pairing.",
        },
    )

    return pairing


@router.get("/pending", response_model=List[PairingOut])
def list_pending(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Return all incoming pending pairing requests across the user's devices."""
    result = []
    for device_id in _get_user_device_ids(db, current_user):
        result.extend(pairing_service.get_pending_requests_for_device(db, device_id))
    return result


@router.get("/paired", response_model=List[PairingOut])
def list_paired(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Return all accepted pairings across the user's devices."""
    result = []
    for device_id in _get_user_device_ids(db, current_user):
        result.extend(pairing_service.get_accepted_pairings_for_device(db, device_id))
    # Deduplicate (a pairing involving two of the user's own devices would appear twice)
    seen = set()
    unique = []
    for p in result:
        if p.id not in seen:
            seen.add(p.id)
            unique.append(p)
    return unique


@router.get("/all", response_model=List[PairingOut])
def list_all(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Return all pairings (any status) across the user's devices."""
    result = []
    for device_id in _get_user_device_ids(db, current_user):
        result.extend(pairing_service.get_all_pairings_for_device(db, device_id))
    seen = set()
    unique = []
    for p in result:
        if p.id not in seen:
            seen.add(p.id)
            unique.append(p)
    return unique
