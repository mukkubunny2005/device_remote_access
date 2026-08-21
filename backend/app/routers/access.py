"""Access Session Router.

Endpoints:
    POST   /access/request       - Request remote access to a paired device
    POST   /access/{id}/respond  - Target device explicitly accepts or rejects
    POST   /access/{id}/end      - Either device terminates the active session
    GET    /access/pending       - Inbound pending requests
    GET    /access/active        - Current active session for user's devices
    GET    /access/history       - Access request and session history
"""

import logging
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.user import User
from app.schemas.session import AccessRequestCreate, AccessRespondRequest, AccessSessionOut
from app.security.jwt import get_current_user
from app.services import session_service
from app.services.device_service import get_devices_by_user
from app.websocket.manager import manager

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/access", tags=["Access Sessions"])


def _get_user_device_ids(db: Session, user: User) -> List[str]:
    return [d.device_id for d in get_devices_by_user(db, user.id)]


async def _notify_device(device_id: str, payload: dict) -> None:
    try:
        await manager.send_to_device(device_id, payload)
    except Exception as exc:
        logger.debug("WS notify failed for %s: %s", device_id, exc)


@router.post("/request", response_model=AccessSessionOut, status_code=status.HTTP_201_CREATED)
async def request_access(
    payload: AccessRequestCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Device A initiates a remote access request to a paired target device (Device B).
    Real-time notification is immediately pushed to Device B via WebSocket.
    """
    my_device_ids = _get_user_device_ids(db, current_user)
    if not my_device_ids:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="You have no registered devices.",
        )

    requester_device_id = next(
        (did for did in my_device_ids if did != payload.target_device_id),
        None,
    )
    if requester_device_id is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot request remote access to your own device.",
        )

    try:
        session = session_service.create_access_request(
            db,
            requester_device_id=requester_device_id,
            target_device_id=payload.target_device_id,
            request_control=payload.request_control,
        )
    except LookupError as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(e))
    except PermissionError as e:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=str(e))
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(e))

    # Push consent prompt event to target device
    await _notify_device(
        payload.target_device_id,
        {
            "type": "access_request",
            "session_id": session.id,
            "requester_device_id": requester_device_id,
            "can_control": session.can_control,
            "expires_at": session.expires_at.isoformat(),
            "message": (
                f"Device {requester_device_id} is requesting remote access "
                f"({'Screen + Control' if session.can_control else 'View Only'})."
            ),
        },
    )

    return session


@router.post("/{session_id}/respond", response_model=AccessSessionOut)
async def respond_to_access(
    session_id: str,
    payload: AccessRespondRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Target device explicitly grants or denies remote access.
    Only the target device's owner may respond.
    """
    my_device_ids = _get_user_device_ids(db, current_user)

    session_record = db.query(session_service.AccessSession).filter(
        session_service.AccessSession.id == session_id
    ).first()

    if not session_record:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Access request not found.")

    if session_record.target_device_id not in my_device_ids:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only the target device may respond to this access request.",
        )

    try:
        session = session_service.respond_to_access_request(
            db,
            session_id=session_id,
            responding_device_id=session_record.target_device_id,
            action=payload.action,
            allow_control=payload.allow_control,
        )
    except LookupError as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(e))
    except PermissionError as e:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=str(e))
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))

    # Notify requester device of approval or rejection
    await _notify_device(
        session.requester_device_id,
        {
            "type": "access_response",
            "session_id": session.id,
            "status": session.status,
            "target_device_id": session.target_device_id,
            "can_control": session.can_control,
            "session_token": session.session_token,
            "message": (
                f"Device {session.target_device_id} "
                f"{'accepted' if session.status == 'active' else 'declined'} your access request."
            ),
        },
    )

    return session


@router.post("/{session_id}/end", response_model=AccessSessionOut)
async def end_session(
    session_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Either the controller (Device A) or target (Device B) can immediately terminate the session.
    """
    my_device_ids = _get_user_device_ids(db, current_user)

    session_record = db.query(session_service.AccessSession).filter(
        session_service.AccessSession.id == session_id
    ).first()

    if not session_record:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Access session not found.")

    actor_device_id = next(
        (did for did in my_device_ids if did in (session_record.requester_device_id, session_record.target_device_id)),
        None,
    )
    if not actor_device_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You are not a participant in this session.",
        )

    try:
        session = session_service.end_access_session(db, session_id, actor_device_id)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))

    # Notify both sides that session has terminated
    other_device_id = (
        session.target_device_id
        if actor_device_id == session.requester_device_id
        else session.requester_device_id
    )
    await _notify_device(
        other_device_id,
        {
            "type": "session_ended",
            "session_id": session.id,
            "ended_by": actor_device_id,
            "message": f"Remote session was terminated by device {actor_device_id}.",
        },
    )

    return session


@router.get("/pending", response_model=List[AccessSessionOut])
def list_pending_requests(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """List pending unexpired inbound access requests for all user's devices."""
    res = []
    for did in _get_user_device_ids(db, current_user):
        res.extend(session_service.get_pending_inbound_requests_for_device(db, did))
    return res


@router.get("/active", response_model=Optional[AccessSessionOut])
def get_active_session(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Get the current active session for any of the user's devices, if one exists."""
    for did in _get_user_device_ids(db, current_user):
        s = session_service.get_active_session_for_device(db, did)
        if s:
            return s
    return None


@router.get("/history", response_model=List[AccessSessionOut])
def list_session_history(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """List all historical and current access requests for user's devices."""
    res = []
    seen = set()
    for did in _get_user_device_ids(db, current_user):
        for s in session_service.get_session_history_for_device(db, did):
            if s.id not in seen:
                seen.add(s.id)
                res.append(s)
    return res
