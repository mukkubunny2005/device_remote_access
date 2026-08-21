"""Tests for WebSocket WebRTC signaling (Offer/Answer/ICE) in active sessions."""

import json
import pytest
from fastapi.testclient import TestClient

from tests.conftest import auth_headers, register_and_login


def _setup_active_session(client: TestClient):
    tokens_a = register_and_login(client, "alice_webrtc@example.com", "Password123")
    tokens_b = register_and_login(client, "bob_webrtc@example.com", "Password123")

    client.post("/devices/register", json={"device_id": "10000001"}, headers=auth_headers(tokens_a))
    client.post("/devices/register", json={"device_id": "20000002"}, headers=auth_headers(tokens_b))
    client.patch("/devices/10000001/status", json={"online": True}, headers=auth_headers(tokens_a))
    client.patch("/devices/20000002/status", json={"online": True}, headers=auth_headers(tokens_b))

    pair_res = client.post("/pairing/request", json={"target_device_id": "20000002"}, headers=auth_headers(tokens_a))
    pid = pair_res.json()["id"]
    client.post(f"/pairing/{pid}/respond", json={"action": "accept"}, headers=auth_headers(tokens_b))

    req_res = client.post("/access/request", json={"target_device_id": "20000002", "request_control": True}, headers=auth_headers(tokens_a))
    sid = req_res.json()["id"]
    client.post(f"/access/{sid}/respond", json={"action": "accept", "allow_control": True}, headers=auth_headers(tokens_b))

    return tokens_a, tokens_b, "10000001", "20000002", sid


class TestWebRTCSignaling:
    def test_webrtc_offer_and_answer_exchange(self, client: TestClient):
        tokens_a, tokens_b, id_a, id_b, sid = _setup_active_session(client)

        with client.websocket_connect(f"/ws/device/{id_a}?token={tokens_a['access_token']}") as ws_a:
            init_a = json.loads(ws_a.receive_text())
            assert init_a["type"] == "connected"

            with client.websocket_connect(f"/ws/device/{id_b}?token={tokens_b['access_token']}") as ws_b:
                init_b = json.loads(ws_b.receive_text())
                assert init_b["type"] == "connected"

                # Device A sends SDP offer to Device B
                offer_msg = {
                    "type": "webrtc_offer",
                    "session_id": sid,
                    "target_device_id": id_b,
                    "sdp": "v=0\r\no=alice ...",
                }
                ws_a.send_text(json.dumps(offer_msg))

                # Device B should receive the forwarded offer
                recvd_b = json.loads(ws_b.receive_text())
                assert recvd_b["type"] == "webrtc_offer"
                assert recvd_b["session_id"] == sid
                assert recvd_b["from_device_id"] == id_a
                assert recvd_b["sdp"] == "v=0\r\no=alice ..."

                # Device B sends SDP answer back to Device A
                answer_msg = {
                    "type": "webrtc_answer",
                    "session_id": sid,
                    "target_device_id": id_a,
                    "sdp": "v=0\r\no=bob ...",
                }
                ws_b.send_text(json.dumps(answer_msg))

                # Device A should receive the answer
                recvd_a = json.loads(ws_a.receive_text())
                assert recvd_a["type"] == "webrtc_answer"
                assert recvd_a["session_id"] == sid
                assert recvd_a["from_device_id"] == id_b
                assert recvd_a["sdp"] == "v=0\r\no=bob ..."

                # Exchange ICE Candidate
                ice_msg = {
                    "type": "webrtc_ice_candidate",
                    "session_id": sid,
                    "target_device_id": id_b,
                    "candidate": {"candidate": "candidate:1 1 UDP ...", "sdpMid": "0", "sdpMLineIndex": 0},
                }
                ws_a.send_text(json.dumps(ice_msg))
                recvd_ice_b = json.loads(ws_b.receive_text())
                assert recvd_ice_b["type"] == "webrtc_ice_candidate"
                assert recvd_ice_b["from_device_id"] == id_a
                assert recvd_ice_b["candidate"]["candidate"] == "candidate:1 1 UDP ..."
