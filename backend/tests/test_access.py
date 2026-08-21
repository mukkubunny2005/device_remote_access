"""Tests for remote access request & session endpoints."""

import pytest
from datetime import datetime, timezone, timedelta
from fastapi.testclient import TestClient

from tests.conftest import auth_headers, register_and_login


def _setup_paired_users(client: TestClient):
    """Setup Alice (11111111) and Bob (22222222), both online, and paired."""
    tokens_a = register_and_login(client, "alice_access@example.com", "Password123")
    tokens_b = register_and_login(client, "bob_access@example.com", "Password123")

    # Register devices
    client.post(
        "/devices/register",
        json={"device_id": "11111111", "device_name": "Alice Phone"},
        headers=auth_headers(tokens_a),
    )
    client.post(
        "/devices/register",
        json={"device_id": "22222222", "device_name": "Bob Phone"},
        headers=auth_headers(tokens_b),
    )

    # Set Bob online (by default register sets online=False or True, let's explicitly set True)
    client.patch("/devices/22222222/status", json={"online": True}, headers=auth_headers(tokens_b))
    client.patch("/devices/11111111/status", json={"online": True}, headers=auth_headers(tokens_a))

    # Create & accept pairing
    pair_res = client.post(
        "/pairing/request",
        json={"target_device_id": "22222222"},
        headers=auth_headers(tokens_a),
    )
    assert pair_res.status_code == 201
    pid = pair_res.json()["id"]

    client.post(
        f"/pairing/{pid}/respond",
        json={"action": "accept"},
        headers=auth_headers(tokens_b),
    )

    return tokens_a, tokens_b, "11111111", "22222222"


class TestCreateAccessRequest:
    def test_request_access_success(self, client: TestClient):
        tokens_a, tokens_b, id_a, id_b = _setup_paired_users(client)

        r = client.post(
            "/access/request",
            json={"target_device_id": id_b, "request_control": True},
            headers=auth_headers(tokens_a),
        )
        assert r.status_code == 201, r.text
        data = r.json()
        assert data["requester_device_id"] == id_a
        assert data["target_device_id"] == id_b
        assert data["status"] == "pending"
        assert data["can_control"] is True
        assert data["view_only"] is False
        assert data["session_token"] is None

    def test_request_access_not_paired_forbidden(self, client: TestClient):
        tokens_a = register_and_login(client, "alice_unpaired@example.com", "Password123")
        tokens_c = register_and_login(client, "carol_unpaired@example.com", "Password123")

        client.post("/devices/register", json={"device_id": "33333333"}, headers=auth_headers(tokens_a))
        client.post("/devices/register", json={"device_id": "44444444"}, headers=auth_headers(tokens_c))
        client.patch("/devices/44444444/status", json={"online": True}, headers=auth_headers(tokens_c))

        # Attempt remote access without prior pairing
        r = client.post(
            "/access/request",
            json={"target_device_id": "44444444", "request_control": True},
            headers=auth_headers(tokens_a),
        )
        assert r.status_code == 403
        assert "not paired" in r.json()["detail"].lower()

    def test_request_access_target_offline(self, client: TestClient):
        tokens_a, tokens_b, id_a, id_b = _setup_paired_users(client)

        # Set Bob offline
        client.patch(f"/devices/{id_b}/status", json={"online": False}, headers=auth_headers(tokens_b))

        r = client.post(
            "/access/request",
            json={"target_device_id": id_b, "request_control": True},
            headers=auth_headers(tokens_a),
        )
        assert r.status_code == 409
        assert "offline" in r.json()["detail"].lower()

    def test_request_access_duplicate_pending(self, client: TestClient):
        tokens_a, tokens_b, id_a, id_b = _setup_paired_users(client)

        client.post(
            "/access/request",
            json={"target_device_id": id_b, "request_control": True},
            headers=auth_headers(tokens_a),
        )
        # Duplicate
        r = client.post(
            "/access/request",
            json={"target_device_id": id_b, "request_control": True},
            headers=auth_headers(tokens_a),
        )
        assert r.status_code == 409


class TestRespondAccessRequest:
    def _create_pending(self, client, tokens_a, id_b):
        r = client.post(
            "/access/request",
            json={"target_device_id": id_b, "request_control": True},
            headers=auth_headers(tokens_a),
        )
        assert r.status_code == 201
        return r.json()["id"]

    def test_accept_access_with_control(self, client: TestClient):
        tokens_a, tokens_b, id_a, id_b = _setup_paired_users(client)
        sid = self._create_pending(client, tokens_a, id_b)

        r = client.post(
            f"/access/{sid}/respond",
            json={"action": "accept", "allow_control": True},
            headers=auth_headers(tokens_b),
        )
        assert r.status_code == 200, r.text
        data = r.json()
        assert data["status"] == "active"
        assert data["can_control"] is True
        assert data["view_only"] is False
        assert data["session_token"] is not None
        assert len(data["session_token"]) == 64

    def test_accept_access_view_only(self, client: TestClient):
        tokens_a, tokens_b, id_a, id_b = _setup_paired_users(client)
        sid = self._create_pending(client, tokens_a, id_b)

        r = client.post(
            f"/access/{sid}/respond",
            json={"action": "accept", "allow_control": False},
            headers=auth_headers(tokens_b),
        )
        assert r.status_code == 200
        data = r.json()
        assert data["status"] == "active"
        assert data["can_control"] is False
        assert data["view_only"] is True
        assert data["session_token"] is not None

    def test_reject_access(self, client: TestClient):
        tokens_a, tokens_b, id_a, id_b = _setup_paired_users(client)
        sid = self._create_pending(client, tokens_a, id_b)

        r = client.post(
            f"/access/{sid}/respond",
            json={"action": "reject", "allow_control": False},
            headers=auth_headers(tokens_b),
        )
        assert r.status_code == 200
        data = r.json()
        assert data["status"] == "rejected"
        assert data["session_token"] is None

    def test_requester_cannot_approve_own_request(self, client: TestClient):
        tokens_a, tokens_b, id_a, id_b = _setup_paired_users(client)
        sid = self._create_pending(client, tokens_a, id_b)

        # Requester A tries to self-approve access on B
        r = client.post(
            f"/access/{sid}/respond",
            json={"action": "accept", "allow_control": True},
            headers=auth_headers(tokens_a),
        )
        assert r.status_code == 403


class TestEndAccessSession:
    def _create_active_session(self, client, tokens_a, tokens_b, id_b):
        r = client.post(
            "/access/request",
            json={"target_device_id": id_b, "request_control": True},
            headers=auth_headers(tokens_a),
        )
        sid = r.json()["id"]
        client.post(
            f"/access/{sid}/respond",
            json={"action": "accept", "allow_control": True},
            headers=auth_headers(tokens_b),
        )
        return sid

    def test_requester_can_end_session(self, client: TestClient):
        tokens_a, tokens_b, id_a, id_b = _setup_paired_users(client)
        sid = self._create_active_session(client, tokens_a, tokens_b, id_b)

        r = client.post(f"/access/{sid}/end", headers=auth_headers(tokens_a))
        assert r.status_code == 200
        assert r.json()["status"] == "ended"
        assert r.json()["ended_at"] is not None

    def test_target_can_end_session(self, client: TestClient):
        tokens_a, tokens_b, id_a, id_b = _setup_paired_users(client)
        sid = self._create_active_session(client, tokens_a, tokens_b, id_b)

        # Target (Device B) terminates the remote access session
        r = client.post(f"/access/{sid}/end", headers=auth_headers(tokens_b))
        assert r.status_code == 200
        assert r.json()["status"] == "ended"


class TestQueryAccessSessions:
    def test_list_pending_requests(self, client: TestClient):
        tokens_a, tokens_b, id_a, id_b = _setup_paired_users(client)
        client.post(
            "/access/request",
            json={"target_device_id": id_b, "request_control": True},
            headers=auth_headers(tokens_a),
        )

        r = client.get("/access/pending", headers=auth_headers(tokens_b))
        assert r.status_code == 200
        assert len(r.json()) == 1
        assert r.json()[0]["target_device_id"] == id_b

    def test_get_active_session(self, client: TestClient):
        tokens_a, tokens_b, id_a, id_b = _setup_paired_users(client)
        r_req = client.post(
            "/access/request",
            json={"target_device_id": id_b, "request_control": True},
            headers=auth_headers(tokens_a),
        )
        sid = r_req.json()["id"]
        client.post(f"/access/{sid}/respond", json={"action": "accept"}, headers=auth_headers(tokens_b))

        r = client.get("/access/active", headers=auth_headers(tokens_a))
        assert r.status_code == 200
        assert r.json() is not None
        assert r.json()["id"] == sid
        assert r.json()["status"] == "active"
