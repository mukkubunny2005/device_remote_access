"""Pairing business logic service."""

import logging
from datetime import datetime, timezone
from typing import List, Optional

from sqlalchemy import or_, and_
from sqlalchemy.orm import Session

from app.models.device import Device
from app.models.pairing import Pairing

logger = logging.getLogger(__name__)


# ── Helpers ────────────────────────────────────────────────────────────────────

def _now() -> datetime:
    return datetime.now(timezone.utc)


def _get_device(db: Session, device_id: str) -> Optional[Device]:
    return db.query(Device).filter(Device.device_id == device_id).first()


# ── Core operations ────────────────────────────────────────────────────────────

def send_pairing_request(
    db: Session,
    requester_device_id: str,
    target_device_id: str,
) -> Pairing:
    """
    Create a pending pairing request from requester → target.

    Rules enforced:
    - Cannot pair with yourself.
    - Target device must exist.
    - No duplicate pending request in either direction.
    - No already-accepted pairing between the two.
    """
    if requester_device_id == target_device_id:
        raise ValueError("A device cannot pair with itself.")

    target = _get_device(db, target_device_id)
    if not target:
        raise LookupError(f"Device '{target_device_id}' not found.")

    # Check for any active pairing between these two devices
    existing = _find_pairing(db, requester_device_id, target_device_id,
                             statuses=["pending", "accepted"])
    if existing:
        if existing.status == "accepted":
            raise ValueError("These devices are already paired.")
        if existing.status == "pending":
            raise ValueError("A pairing request is already pending.")

    pairing = Pairing(
        requester_device_id=requester_device_id,
        target_device_id=target_device_id,
        status="pending",
    )
    db.add(pairing)
    db.commit()
    db.refresh(pairing)
    logger.info("Pairing request created: %s → %s", requester_device_id, target_device_id)
    return pairing


def respond_to_pairing(
    db: Session,
    pairing_id: str,
    responding_device_id: str,
    action: str,  # "accept" | "reject"
) -> Pairing:
    """
    Device B (target) accepts or rejects a pending pairing request.
    Only the target device may respond.
    """
    pairing = db.query(Pairing).filter(Pairing.id == pairing_id).first()
    if not pairing:
        raise LookupError("Pairing request not found.")
    if pairing.target_device_id != responding_device_id:
        raise PermissionError("Only the target device may respond to this request.")
    if pairing.status != "pending":
        raise ValueError(f"Cannot respond to a pairing with status '{pairing.status}'.")

    if action == "accept":
        pairing.status = "accepted"
        pairing.accepted_at = _now()
        logger.info("Pairing accepted: %s ↔ %s", pairing.requester_device_id, pairing.target_device_id)
    elif action == "reject":
        pairing.status = "rejected"
        logger.info("Pairing rejected: %s → %s", pairing.requester_device_id, pairing.target_device_id)
    else:
        raise ValueError(f"Unknown action '{action}'.")

    db.commit()
    db.refresh(pairing)
    return pairing


def revoke_pairing(
    db: Session,
    pairing_id: str,
    requesting_device_id: str,
) -> Pairing:
    """
    Either device can revoke an accepted (or pending) pairing.
    """
    pairing = db.query(Pairing).filter(Pairing.id == pairing_id).first()
    if not pairing:
        raise LookupError("Pairing not found.")

    is_participant = (
        pairing.requester_device_id == requesting_device_id
        or pairing.target_device_id == requesting_device_id
    )
    if not is_participant:
        raise PermissionError("You are not a participant in this pairing.")
    if pairing.status == "revoked":
        raise ValueError("Pairing is already revoked.")

    pairing.status = "revoked"
    pairing.revoked_at = _now()
    db.commit()
    db.refresh(pairing)
    logger.info("Pairing revoked: %s ↔ %s by %s",
                pairing.requester_device_id, pairing.target_device_id, requesting_device_id)
    return pairing


# ── Queries ────────────────────────────────────────────────────────────────────

def _find_pairing(
    db: Session,
    device_a: str,
    device_b: str,
    statuses: Optional[List[str]] = None,
) -> Optional[Pairing]:
    """Find a pairing between two devices (in either direction)."""
    q = db.query(Pairing).filter(
        or_(
            and_(Pairing.requester_device_id == device_a, Pairing.target_device_id == device_b),
            and_(Pairing.requester_device_id == device_b, Pairing.target_device_id == device_a),
        )
    )
    if statuses:
        q = q.filter(Pairing.status.in_(statuses))
    return q.first()


def get_pairing_by_id(db: Session, pairing_id: str) -> Optional[Pairing]:
    return db.query(Pairing).filter(Pairing.id == pairing_id).first()


def get_pending_requests_for_device(db: Session, device_id: str) -> List[Pairing]:
    """Return all pending inbound pairing requests for a device."""
    return (
        db.query(Pairing)
        .filter(Pairing.target_device_id == device_id, Pairing.status == "pending")
        .order_by(Pairing.created_at.desc())
        .all()
    )


def get_accepted_pairings_for_device(db: Session, device_id: str) -> List[Pairing]:
    """Return all accepted pairings that include this device."""
    return (
        db.query(Pairing)
        .filter(
            or_(
                Pairing.requester_device_id == device_id,
                Pairing.target_device_id == device_id,
            ),
            Pairing.status == "accepted",
        )
        .order_by(Pairing.accepted_at.desc())
        .all()
    )


def get_all_pairings_for_device(db: Session, device_id: str) -> List[Pairing]:
    """Return all pairings (any status) that include this device."""
    return (
        db.query(Pairing)
        .filter(
            or_(
                Pairing.requester_device_id == device_id,
                Pairing.target_device_id == device_id,
            )
        )
        .order_by(Pairing.created_at.desc())
        .all()
    )


def are_paired(db: Session, device_a: str, device_b: str) -> bool:
    """Return True if the two devices have an accepted pairing."""
    return _find_pairing(db, device_a, device_b, statuses=["accepted"]) is not None
