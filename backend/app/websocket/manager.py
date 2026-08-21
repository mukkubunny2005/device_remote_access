"""WebSocket connection manager.

Phase 1: Tracks per-device WebSocket connections and handles heartbeat/presence.
Phase 3: Will add signaling (offer/answer/ICE) and FCM fallback.

WebSocket endpoint: WS /ws/device/{device_id}
Authentication: JWT passed as query param `token=<access_token>`
"""

import asyncio
import json
import logging
from typing import Dict, Optional

from fastapi import WebSocket, WebSocketDisconnect

logger = logging.getLogger(__name__)

# Ping interval and timeout (seconds)
PING_INTERVAL = 30
PING_TIMEOUT = 10


class ConnectionManager:
    """Manages active WebSocket connections indexed by device_id."""

    def __init__(self):
        # device_id → WebSocket
        self._connections: Dict[str, WebSocket] = {}
        # device_id → asyncio.Task (ping loop)
        self._ping_tasks: Dict[str, asyncio.Task] = {}

    # ── Connection lifecycle ───────────────────────────────────────────────────

    async def connect(self, device_id: str, websocket: WebSocket) -> None:
        await websocket.accept()
        # Disconnect any stale connection for the same device
        await self._disconnect_existing(device_id)
        self._connections[device_id] = websocket
        logger.info("WS connected: device=%s", device_id)
        # Start ping loop
        task = asyncio.create_task(self._ping_loop(device_id, websocket))
        self._ping_tasks[device_id] = task

    async def disconnect(self, device_id: str) -> None:
        self._connections.pop(device_id, None)
        task = self._ping_tasks.pop(device_id, None)
        if task:
            task.cancel()
        logger.info("WS disconnected: device=%s", device_id)

    async def _disconnect_existing(self, device_id: str) -> None:
        existing = self._connections.pop(device_id, None)
        if existing:
            try:
                await existing.close()
            except Exception:
                pass
        task = self._ping_tasks.pop(device_id, None)
        if task:
            task.cancel()

    # ── Messaging ──────────────────────────────────────────────────────────────

    async def send_to_device(self, device_id: str, message: dict) -> bool:
        """Send a JSON message to a connected device. Returns False if offline."""
        ws = self._connections.get(device_id)
        if ws is None:
            return False
        try:
            await ws.send_text(json.dumps(message))
            return True
        except Exception as exc:
            logger.warning("Failed to send to device %s: %s", device_id, exc)
            await self.disconnect(device_id)
            return False

    def is_connected(self, device_id: str) -> bool:
        return device_id in self._connections

    # ── Heartbeat ─────────────────────────────────────────────────────────────

    async def _ping_loop(self, device_id: str, websocket: WebSocket) -> None:
        """Periodically ping the client to detect stale connections."""
        try:
            while True:
                await asyncio.sleep(PING_INTERVAL)
                if device_id not in self._connections:
                    break
                try:
                    await websocket.send_text(json.dumps({"type": "ping"}))
                except Exception:
                    logger.info("Ping failed for device=%s — removing connection", device_id)
                    await self.disconnect(device_id)
                    break
        except asyncio.CancelledError:
            pass


# Singleton
manager = ConnectionManager()
