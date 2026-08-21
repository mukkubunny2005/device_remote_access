"""Tests for pairing endpoints."""

import pytest
from fastapi.testclient import TestClient

from tests.conftest import auth_headers, register_and_login

# ── Helpers ────────────────────────────────────────────────────────────────────

def _register_device(client, tokens, device_id="12345678", name="Test Phone"):
    r = client.post(
        "/devices/register",
        json={"device_id": device_id, "device_name": name},
        headers=auth_headers(tokens),
    )
    assert r.status_code == 201, r.text
    return r.json()


def _setup_two_users(client):
    """Register two users, each with one device. Return (tokens_a, tokens_b, id_a, id_b)."""
    tokens_a = register_and_login(client, "alice@example.com", "Password123")
    tokens_b = register_and_login(client, "bob@example.com", "Password123")
    _register_device(client, tokens_a, "11111111", "Alice Phone")
    _register_device(client, tokens_b, "22222222", "Bob Phone")
    return tokens_a, tokens_b, "11111111", "22222222"


# ── Send pairing request ───────────────────────────────────────────────────────

class TestSendPairingRequest:
    def test_send_request_success(self, client: TestClient):
        tokens_a, tokens_b, id_a, id_b = _setup_two_users(client)
        r = client.post(
            "/pairing/request",
            json={"target_device_id": id_b},
            headers=auth_headers(tokens_a),
        )
        assert r.status_code == 201, r.text
        data = r.json()
        assert data["requester_device_id"] == id_a
        assert data["target_device_id"] == id_b
        assert data["status"] == "pending"

    def test_send_request_device_not_found(self, client: TestClient):
        tokens_a = register_and_login(client, "a@example.com", "Password123")
        _register_device(client, tokens_a, "11111111")
        r = client.post(
            "/pairing/request",
            json={"target_device_id": "99999999"},
            headers=auth_headers(tokens_a),
        )
        assert r.status_code == 404

    def test_send_request_no_device_registered(self, client: TestClient):
        tokens_a = register_and_login(client)
        r = client.post(
            "/pairing/request",
            json={"target_device_id": "99999999"},
            headers=auth_headers(tokens_a),
        )
        assert r.status_code == 400

    def test_send_request_duplicate_pending(self, client: TestClient):
        tokens_a, tokens_b, id_a, id_b = _setup_two_users(client)
        client.post("/pairing/request", json={"target_device_id": id_b},
                    headers=auth_headers(tokens_a))
        r = client.post("/pairing/request", json={"target_device_id": id_b},
                        headers=auth_headers(tokens_a))
        assert r.status_code == 409

    def test_send_request_requires_auth(self, client: TestClient):
        r = client.post("/pairing/request", json={"target_device_id": "12345678"})
        assert r.status_code == 403


# ── Respond to pairing ─────────────────────────────────────────────────────────

class TestRespondToPairing:
    def _create_request(self, client, tokens_a, id_b):
        r = client.post("/pairing/request", json={"target_device_id": id_b},
                        headers=auth_headers(tokens_a))
        assert r.status_code == 201
        return r.json()["id"]

    def test_accept_pairing(self, client: TestClient):
        tokens_a, tokens_b, id_a, id_b = _setup_two_users(client)
        pid = self._create_request(client, tokens_a, id_b)
        r = client.post(f"/pairing/{pid}/respond",
                        json={"action": "accept"},
                        headers=auth_headers(tokens_b))
        assert r.status_code == 200, r.text
        assert r.json()["status"] == "accepted"
        assert r.json()["accepted_at"] is not None

    def test_reject_pairing(self, client: TestClient):
        tokens_a, tokens_b, id_a, id_b = _setup_two_users(client)
        pid = self._create_request(client, tokens_a, id_b)
        r = client.post(f"/pairing/{pid}/respond",
                        json={"action": "reject"},
                        headers=auth_headers(tokens_b))
        assert r.status_code == 200
        assert r.json()["status"] == "rejected"

    def test_only_target_can_respond(self, client: TestClient):
        """Requester (A) cannot accept their own request."""
        tokens_a, tokens_b, id_a, id_b = _setup_two_users(client)
        pid = self._create_request(client, tokens_a, id_b)
        r = client.post(f"/pairing/{pid}/respond",
                        json={"action": "accept"},
                        headers=auth_headers(tokens_a))  # A trying to accept
        assert r.status_code == 403

    def test_cannot_respond_twice(self, client: TestClient):
        tokens_a, tokens_b, id_a, id_b = _setup_two_users(client)
        pid = self._create_request(client, tokens_a, id_b)
        client.post(f"/pairing/{pid}/respond", json={"action": "accept"},
                    headers=auth_headers(tokens_b))
        r = client.post(f"/pairing/{pid}/respond", json={"action": "reject"},
                        headers=auth_headers(tokens_b))
        assert r.status_code == 400

    def test_cannot_pair_again_when_accepted(self, client: TestClient):
        tokens_a, tokens_b, id_a, id_b = _setup_two_users(client)
        pid = self._create_request(client, tokens_a, id_b)
        client.post(f"/pairing/{pid}/respond", json={"action": "accept"},
                    headers=auth_headers(tokens_b))
        r = client.post("/pairing/request", json={"target_device_id": id_b},
                        headers=auth_headers(tokens_a))
        assert r.status_code == 409


# ── Revoke pairing ─────────────────────────────────────────────────────────────

class TestRevokePairing:
    def _accepted_pairing_id(self, client, tokens_a, tokens_b, id_b):
        r = client.post("/pairing/request", json={"target_device_id": id_b},
                        headers=auth_headers(tokens_a))
        pid = r.json()["id"]
        client.post(f"/pairing/{pid}/respond", json={"action": "accept"},
                    headers=auth_headers(tokens_b))
        return pid

    def test_requester_can_revoke(self, client: TestClient):
        tokens_a, tokens_b, id_a, id_b = _setup_two_users(client)
        pid = self._accepted_pairing_id(client, tokens_a, tokens_b, id_b)
        r = client.delete(f"/pairing/{pid}", headers=auth_headers(tokens_a))
        assert r.status_code == 200
        assert r.json()["status"] == "revoked"

    def test_target_can_revoke(self, client: TestClient):
        tokens_a, tokens_b, id_a, id_b = _setup_two_users(client)
        pid = self._accepted_pairing_id(client, tokens_a, tokens_b, id_b)
        r = client.delete(f"/pairing/{pid}", headers=auth_headers(tokens_b))
        assert r.status_code == 200
        assert r.json()["status"] == "revoked"

    def test_third_party_cannot_revoke(self, client: TestClient):
        tokens_a, tokens_b, id_a, id_b = _setup_two_users(client)
        pid = self._accepted_pairing_id(client, tokens_a, tokens_b, id_b)
        tokens_c = register_and_login(client, "carol@example.com", "Password123")
        _register_device(client, tokens_c, "33333333", "Carol Phone")
        r = client.delete(f"/pairing/{pid}", headers=auth_headers(tokens_c))
        assert r.status_code == 403

    def test_revoke_twice_fails(self, client: TestClient):
        tokens_a, tokens_b, id_a, id_b = _setup_two_users(client)
        pid = self._accepted_pairing_id(client, tokens_a, tokens_b, id_b)
        client.delete(f"/pairing/{pid}", headers=auth_headers(tokens_a))
        r = client.delete(f"/pairing/{pid}", headers=auth_headers(tokens_a))
        assert r.status_code == 400


# ── List pairings ──────────────────────────────────────────────────────────────

class TestListPairings:
    def test_list_pending(self, client: TestClient):
        tokens_a, tokens_b, id_a, id_b = _setup_two_users(client)
        client.post("/pairing/request", json={"target_device_id": id_b},
                    headers=auth_headers(tokens_a))
        r = client.get("/pairing/pending", headers=auth_headers(tokens_b))
        assert r.status_code == 200
        assert len(r.json()) == 1

    def test_list_paired(self, client: TestClient):
        tokens_a, tokens_b, id_a, id_b = _setup_two_users(client)
        r2 = client.post("/pairing/request", json={"target_device_id": id_b},
                         headers=auth_headers(tokens_a))
        pid = r2.json()["id"]
        client.post(f"/pairing/{pid}/respond", json={"action": "accept"},
                    headers=auth_headers(tokens_b))
        r = client.get("/pairing/paired", headers=auth_headers(tokens_a))
        assert r.status_code == 200
        assert len(r.json()) == 1
        assert r.json()[0]["status"] == "accepted"

    def test_list_all(self, client: TestClient):
        tokens_a, tokens_b, id_a, id_b = _setup_two_users(client)
        client.post("/pairing/request", json={"target_device_id": id_b},
                    headers=auth_headers(tokens_a))
        r = client.get("/pairing/all", headers=auth_headers(tokens_a))
        assert r.status_code == 200
        assert len(r.json()) >= 1
