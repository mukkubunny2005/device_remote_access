"""Tests for device endpoints."""

import pytest
from fastapi.testclient import TestClient

from tests.conftest import auth_headers, register_and_login

VALID_DEVICE_PAYLOAD = {
    "device_id": "12345678",
    "device_name": "Test Phone",
    "platform": "android",
    "app_version": "1.0.0",
}


class TestDeviceRegister:
    def test_register_device_success(self, client: TestClient):
        tokens = register_and_login(client)
        resp = client.post(
            "/devices/register",
            json=VALID_DEVICE_PAYLOAD,
            headers=auth_headers(tokens),
        )
        assert resp.status_code == 201
        data = resp.json()
        assert data["device_id"] == "12345678"
        assert data["device_name"] == "Test Phone"
        assert data["online"] is True

    def test_register_requires_auth(self, client: TestClient):
        resp = client.post("/devices/register", json=VALID_DEVICE_PAYLOAD)
        assert resp.status_code == 403

    def test_register_invalid_device_id_alpha(self, client: TestClient):
        tokens = register_and_login(client)
        resp = client.post(
            "/devices/register",
            json={**VALID_DEVICE_PAYLOAD, "device_id": "1234ABCD"},
            headers=auth_headers(tokens),
        )
        assert resp.status_code == 422

    def test_register_invalid_device_id_short(self, client: TestClient):
        tokens = register_and_login(client)
        resp = client.post(
            "/devices/register",
            json={**VALID_DEVICE_PAYLOAD, "device_id": "1234"},
            headers=auth_headers(tokens),
        )
        assert resp.status_code == 422

    def test_register_invalid_device_id_long(self, client: TestClient):
        tokens = register_and_login(client)
        resp = client.post(
            "/devices/register",
            json={**VALID_DEVICE_PAYLOAD, "device_id": "123456789"},
            headers=auth_headers(tokens),
        )
        assert resp.status_code == 422

    def test_register_device_idempotent_same_user(self, client: TestClient):
        """Re-registering same device_id for same user should succeed (update)."""
        tokens = register_and_login(client)
        client.post("/devices/register", json=VALID_DEVICE_PAYLOAD, headers=auth_headers(tokens))
        resp = client.post(
            "/devices/register",
            json={**VALID_DEVICE_PAYLOAD, "device_name": "Updated Name"},
            headers=auth_headers(tokens),
        )
        assert resp.status_code == 201
        assert resp.json()["device_name"] == "Updated Name"

    def test_register_device_conflict_different_user(self, client: TestClient):
        """Same device_id registered by a different user should return 409."""
        tokens_a = register_and_login(client, "user_a@example.com", "Password123")
        tokens_b = register_and_login(client, "user_b@example.com", "Password123")

        client.post("/devices/register", json=VALID_DEVICE_PAYLOAD, headers=auth_headers(tokens_a))
        resp = client.post("/devices/register", json=VALID_DEVICE_PAYLOAD, headers=auth_headers(tokens_b))
        assert resp.status_code == 409


class TestMyDevices:
    def test_list_my_devices(self, client: TestClient):
        tokens = register_and_login(client)
        client.post("/devices/register", json=VALID_DEVICE_PAYLOAD, headers=auth_headers(tokens))
        resp = client.get("/devices/me", headers=auth_headers(tokens))
        assert resp.status_code == 200
        devices = resp.json()
        assert len(devices) == 1
        assert devices[0]["device_id"] == "12345678"

    def test_list_empty_for_new_user(self, client: TestClient):
        tokens = register_and_login(client)
        resp = client.get("/devices/me", headers=auth_headers(tokens))
        assert resp.status_code == 200
        assert resp.json() == []


class TestDeviceLookup:
    def test_lookup_existing_device(self, client: TestClient):
        tokens = register_and_login(client)
        client.post("/devices/register", json=VALID_DEVICE_PAYLOAD, headers=auth_headers(tokens))
        resp = client.get("/devices/12345678", headers=auth_headers(tokens))
        assert resp.status_code == 200
        data = resp.json()
        assert data["device_id"] == "12345678"
        assert "device_name" in data
        assert "online" in data

    def test_lookup_nonexistent_device(self, client: TestClient):
        tokens = register_and_login(client)
        resp = client.get("/devices/99999999", headers=auth_headers(tokens))
        assert resp.status_code == 404

    def test_lookup_requires_auth(self, client: TestClient):
        resp = client.get("/devices/12345678")
        assert resp.status_code == 403


class TestDeviceStatus:
    def test_update_status(self, client: TestClient):
        tokens = register_and_login(client)
        client.post("/devices/register", json=VALID_DEVICE_PAYLOAD, headers=auth_headers(tokens))
        resp = client.patch(
            "/devices/12345678/status",
            json={"online": False},
            headers=auth_headers(tokens),
        )
        assert resp.status_code == 200
        assert resp.json()["online"] is False

    def test_update_status_other_user_forbidden(self, client: TestClient):
        tokens_a = register_and_login(client, "owner@example.com", "Password123")
        tokens_b = register_and_login(client, "attacker@example.com", "Password123")
        client.post("/devices/register", json=VALID_DEVICE_PAYLOAD, headers=auth_headers(tokens_a))
        resp = client.patch(
            "/devices/12345678/status",
            json={"online": False},
            headers=auth_headers(tokens_b),
        )
        assert resp.status_code == 403
