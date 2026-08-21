"""Remote access session business logic service."""

import logging
import secrets
from datetime import datetime, timezone, timedelta
from typing import List, Optional

from sqlalchemy import or_, and_
from sqlalchemy.orm import Session

from app.models.device import Device
from app.models.session import AccessSession
from app.services import pairing_service

logger = logging.getLogger(__name__)

PENDING_TIMEOUT_SECONDS = 60


def _now() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


def _get_device(db: Session, device_id: str) -> Optional[Device]:
    return db.query(Device).filter(Device.device_id == device_id).first()


def cleanup_expired_sessions(db: Session) -> None:
    """Mark any pending sessions whose expires_at has passed as expired."""
    now = _now()
    stale = (
        db.query(AccessSession)
        .filter(AccessSession.status == "pending", AccessSession.expires_at < now)
        .all()
    )
    for s in stale:
        s.status = "expired"
    if stale:
        db.commit()


def create_access_request(
    db: Session,
    requester_device_id: str,
    target_device_id: str,
    request_control: bool = True,
) -> AccessSession:
    """
    Initiate a remote access session request from requester -> target.

    Enforces:
    - Devices must not be identical.
    - Devices must have an active accepted pairing.
    - Target device must exist and be online.
    - Target device must not already have an ongoing active session.
    - No existing pending request between these devices.
    """
    cleanup_expired_sessions(db)

    if requester_device_id == target_device_id:
        raise ValueError("Cannot request remote access to the same device.")

    target = _get_device(db, target_device_id)
    if not target:
        raise LookupError(f"Target device '{target_device_id}' not found.")

    if not target.online:
        raise ValueError(f"Target device '{target_device_id}' is currently offline.")

    # Explicit requirement: Must be paired first
    if not pairing_service.are_paired(db, requester_device_id, target_device_id):
        raise PermissionError(
            f"Device '{requester_device_id}' is not paired with device '{target_device_id}'. "
            "Pairing is required before remote access can be requested."
        )

    # Check if target is already in an active session
    active_session = (
        db.query(AccessSession)
        .filter(
            or_(
                AccessSession.requester_device_id == target_device_id,
                AccessSession.target_device_id == target_device_id,
            ),
            AccessSession.status == "active",
        )
        .first()
    )
    if active_session:
        raise ValueError(f"Device '{target_device_id}' is currently in an active remote session.")

    # Check if there is already a pending request
    pending = (
        db.query(AccessSession)
        .filter(
            AccessSession.requester_device_id == requester_device_id,
            AccessSession.target_device_id == target_device_id,
            AccessSession.status == "pending",
        )
        .first()
    )
    if pending:
        raise ValueError("An access request to this device is already pending.")

    now = _now()
    session = AccessSession(
        requester_device_id=requester_device_id,
        target_device_id=target_device_id,
        status="pending",
        view_only=not request_control,
        can_control=request_control,
        created_at=now,
        expires_at=now + timedelta(seconds=PENDING_TIMEOUT_SECONDS),
    )
    db.add(session)
    db.commit()
    db.refresh(session)
    logger.info("Access request created: %s -> %s (id: %s)", requester_device_id, target_device_id, session.id)
    return session


def respond_to_access_request(
    db: Session,
    session_id: str,
    responding_device_id: str,
    action: str,  # "accept" | "reject"
    allow_control: bool = True,
) -> AccessSession:
    """
    Target device explicitly accepts or rejects the remote access request.
    Only the target device can respond.
    """
    cleanup_expired_sessions(db)

    session = db.query(AccessSession).filter(AccessSession.id == session_id).first()
    if not session:
        raise LookupError("Access session request not found.")

    if session.target_device_id != responding_device_id:
        raise PermissionError("Only the target device can respond to this access request.")

    if session.status == "expired" or session.is_expired():
        session.status = "expired"
        db.commit()
        raise ValueError("This access request has expired.")

    if session.status != "pending":
        raise ValueError(f"Cannot respond to a session with status '{session.status}'.")

    now = _now()
    if action == "accept":
        session.status = "active"
        session.accepted_at = now
        session.can_control = allow_control
        session.view_only = not allow_control
        session.session_token = secrets.token_hex(32)
        logger.info(
            "Access session accepted: %s -> %s (control=%s, token issued)",
            session.requester_device_id,
            session.target_device_id,
            allow_control,
        )
    elif action == "reject":
        session.status = "rejected"
        session.ended_at = now
        logger.info("Access session rejected: %s -> %s", session.requester_device_id, session.target_device_id)
    else:
        raise ValueError(f"Unknown response action '{action}'.")

    db.commit()
    db.refresh(session)
    return session


def end_access_session(
    db: Session,
    session_id: str,
    actor_device_id: str,
) -> AccessSession:
    """
    Either participant can terminate an active remote session at any time.
    """
    session = db.query(AccessSession).filter(AccessSession.id == session_id).first()
    if not session:
        raise LookupError("Access session not found.")

    is_participant = (
        session.requester_device_id == actor_device_id
        or session.target_device_id == actor_device_id
    )
    if not is_participant:
        raise PermissionError("You are not a participant in this access session.")

    if session.status != "active" and session.status != "pending":
        raise ValueError(f"Session is already in state '{session.status}'.")

    session.status = "ended"
    session.ended_at = _now()
    db.commit()
    db.refresh(session)
    logger.info(
        "Access session ended: %s <-> %s by %s",
        session.requester_device_id,
        session.target_device_id,
        actor_device_id,
    )
    return session


def get_active_session_for_device(db: Session, device_id: str) -> Optional[AccessSession]:
    """Return current active session involving this device, if any."""
    return (
        db.query(AccessSession)
        .filter(
            or_(
                AccessSession.requester_device_id == device_id,
                AccessSession.target_device_id == device_id,
            ),
            AccessSession.status == "active",
        )
        .first()
    )


def get_pending_inbound_requests_for_device(db: Session, device_id: str) -> List[AccessSession]:
    """Return unexpired pending inbound requests for this device."""
    cleanup_expired_sessions(db)
    return (
        db.query(AccessSession)
        .filter(
            AccessSession.target_device_id == device_id,
            AccessSession.status == "pending",
        )
        .order_by(AccessSession.created_at.desc())
        .all()
    )


def get_session_history_for_device(db: Session, device_id: str) -> List[AccessSession]:
    """Return all session history involving this device."""
    cleanup_expired_sessions(db)
    return (
        db.query(AccessSession)
        .filter(
            or_(
                AccessSession.requester_device_id == device_id,
                AccessSession.target_device_id == device_id,
            )
        )
        .order_by(AccessSession.created_at.desc())
        .all()
    )
