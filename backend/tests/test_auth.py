"""Tests for authentication endpoints."""

import pytest
from fastapi.testclient import TestClient

from tests.conftest import auth_headers, register_and_login


class TestRegister:
    def test_register_success(self, client: TestClient):
        resp = client.post(
            "/auth/register",
            json={"email": "alice@example.com", "password": "Password123"},
        )
        assert resp.status_code == 201
        data = resp.json()
        assert "access_token" in data
        assert "refresh_token" in data
        assert data["token_type"] == "bearer"

    def test_register_duplicate_email(self, client: TestClient):
        client.post("/auth/register", json={"email": "bob@example.com", "password": "Password123"})
        resp = client.post("/auth/register", json={"email": "bob@example.com", "password": "Different123"})
        assert resp.status_code == 409

    def test_register_invalid_email(self, client: TestClient):
        resp = client.post("/auth/register", json={"email": "not-an-email", "password": "Password123"})
        assert resp.status_code == 422

    def test_register_short_password(self, client: TestClient):
        resp = client.post("/auth/register", json={"email": "charlie@example.com", "password": "short"})
        assert resp.status_code == 422


class TestLogin:
    def test_login_success(self, client: TestClient):
        register_and_login(client, "dave@example.com", "Password123")
        resp = client.post("/auth/login", json={"email": "dave@example.com", "password": "Password123"})
        assert resp.status_code == 200
        data = resp.json()
        assert "access_token" in data

    def test_login_wrong_password(self, client: TestClient):
        register_and_login(client, "eve@example.com", "Password123")
        resp = client.post("/auth/login", json={"email": "eve@example.com", "password": "WrongPass"})
        assert resp.status_code == 401

    def test_login_unknown_user(self, client: TestClient):
        resp = client.post("/auth/login", json={"email": "ghost@example.com", "password": "Password123"})
        assert resp.status_code == 401


class TestRefresh:
    def test_refresh_success(self, client: TestClient):
        tokens = register_and_login(client)
        resp = client.post("/auth/refresh", json={"refresh_token": tokens["refresh_token"]})
        assert resp.status_code == 200
        assert "access_token" in resp.json()

    def test_refresh_invalid_token(self, client: TestClient):
        resp = client.post("/auth/refresh", json={"refresh_token": "garbage.token.here"})
        assert resp.status_code == 401


class TestMe:
    def test_me_authenticated(self, client: TestClient):
        tokens = register_and_login(client)
        resp = client.get("/auth/me", headers=auth_headers(tokens))
        assert resp.status_code == 200
        data = resp.json()
        assert data["email"] == "test@example.com"

    def test_me_unauthenticated(self, client: TestClient):
        resp = client.get("/auth/me")
        assert resp.status_code == 403

    def test_me_invalid_token(self, client: TestClient):
        resp = client.get("/auth/me", headers={"Authorization": "Bearer bad.token"})
        assert resp.status_code == 401


class TestLogout:
    def test_logout(self, client: TestClient):
        tokens = register_and_login(client)
        resp = client.post("/auth/logout", headers=auth_headers(tokens))
        assert resp.status_code == 204
