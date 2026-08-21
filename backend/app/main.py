"""FastAPI application entry point.

Remote Access — Backend
Phase 1: Device registration, authentication, presence.
"""

import json
import logging
import logging.config
from contextlib import asynccontextmanager

from fastapi import FastAPI, Query, WebSocket, WebSocketDisconnect, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address
from sqlalchemy import text

from app.config import get_settings
from app.database import Base, SessionLocal, engine
from app.routers import auth as auth_router
from app.routers import devices as devices_router
from app.routers import pairing as pairing_router
from app.routers import access as access_router
from app.security.jwt import decode_access_token
from app.services.device_service import get_device_by_device_id, update_device_status
from app.websocket.manager import manager

# ── Logging ────────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)-8s | %(name)s | %(message)s",
)
logger = logging.getLogger("remote_access")

settings = get_settings()

# ── Rate limiter ───────────────────────────────────────────────────────────────
limiter = Limiter(key_func=get_remote_address, default_limits=["200/minute"])


# ── Lifespan ───────────────────────────────────────────────────────────────────
@asynccontextmanager
async def lifespan(app: FastAPI):
    # Create tables on startup (dev mode).
    # In production use Alembic migrations instead.
    Base.metadata.create_all(bind=engine)
    logger.info("Database tables ensured.")
    yield
    logger.info("Application shutting down.")


# ── App ────────────────────────────────────────────────────────────────────────
app = FastAPI(
    title="Remote Access API",
    description=(
        "Production-quality remote Android device access backend. "
        "Remote access requires explicit consent from the target device."
    ),
    version="1.0.0",
    lifespan=lifespan,
)

# Rate limiting
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.allowed_origins_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Routers ────────────────────────────────────────────────────────────────────
app.include_router(auth_router.router)
app.include_router(devices_router.router)
app.include_router(pairing_router.router)
app.include_router(access_router.router)


# ── Health check ───────────────────────────────────────────────────────────────
@app.get("/health", tags=["Health"])
def health():
    """Liveness probe."""
    return {"status": "ok", "version": "1.0.0"}


# ── WebSocket ──────────────────────────────────────────────────────────────────
@app.websocket("/ws/device/{device_id}")
async def device_websocket(
    websocket: WebSocket,
    device_id: str,
    token: str = Query(..., description="JWT access token"),
):
    """
    Authenticated WebSocket endpoint for a device.

    Authentication: pass ?token=<access_token> in query string.
    Phase 1: Presence / heartbeat only.
    Phase 3: Will handle signaling (offer/answer/ICE).
    """
    # ── Authenticate ───────────────────────────────────────────────────────────
    try:
        user_id = decode_access_token(token)
    except Exception:
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
        return

    # ── Verify device ownership ────────────────────────────────────────────────
    db = SessionLocal()
    try:
        device = get_device_by_device_id(db, device_id)
        if not device or device.user_id != user_id:
            await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
            return

        # Mark online
        update_device_status(db, device_id, online=True)
    finally:
        db.close()

    await manager.connect(device_id, websocket)

    try:
        await websocket.send_text(json.dumps({"type": "connected", "device_id": device_id}))

        while True:
            raw = await websocket.receive_text()
            try:
                msg = json.loads(raw)
            except json.JSONDecodeError:
                continue

            msg_type = msg.get("type", "")

            if msg_type == "pong":
                # Client acknowledged our ping — connection is alive
                pass
            elif msg_type == "heartbeat":
                # Explicit heartbeat from client
                db2 = SessionLocal()
                try:
                    update_device_status(db2, device_id, online=True)
                finally:
                    db2.close()
                await websocket.send_text(json.dumps({"type": "heartbeat_ack"}))
            elif msg_type in ("webrtc_offer", "webrtc_answer", "webrtc_ice_candidate"):
                # WebRTC Signaling routing (Phase 4)
                session_id = msg.get("session_id")
                target_peer_id = msg.get("target_device_id")
                if not session_id or not target_peer_id:
                    continue

                db_ws = SessionLocal()
                try:
                    from app.models.session import AccessSession
                    session_rec = db_ws.query(AccessSession).filter(AccessSession.id == session_id).first()
                    if not session_rec or session_rec.status != "active":
                        logger.warning("Rejected signaling msg=%s: session %s not active", msg_type, session_id)
                        continue

                    # Verify device_id and target_peer_id are the session participants
                    participants = {session_rec.requester_device_id, session_rec.target_device_id}
                    if device_id not in participants or target_peer_id not in participants:
                        logger.warning("Rejected signaling: sender %s / target %s not in session %s",
                                       device_id, target_peer_id, session_id)
                        continue

                    # Forward signaling message to target peer
                    forward_payload = {
                        "type": msg_type,
                        "session_id": session_id,
                        "from_device_id": device_id,
                        "target_device_id": target_peer_id,
                        "sdp": msg.get("sdp"),
                        "candidate": msg.get("candidate"),
                    }
                    await manager.send_to_device(target_peer_id, forward_payload)
                    logger.info("Forwarded %s from %s -> %s (session %s)",
                                msg_type, device_id, target_peer_id, session_id)
                finally:
                    db_ws.close()
            else:
                logger.debug("Received unknown WS message type=%s from device=%s", msg_type, device_id)

    except WebSocketDisconnect:
        pass
    except Exception as exc:
        logger.error("WS error for device=%s: %s", device_id, exc)
    finally:
        await manager.disconnect(device_id)
        db3 = SessionLocal()
        try:
            update_device_status(db3, device_id, online=False)
        finally:
            db3.close()
        logger.info("Device %s went offline.", device_id)
