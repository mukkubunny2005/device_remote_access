# Remote Access — Backend

A **FastAPI** backend for the Remote Access application.

> ⚠️ **Consent-first**: Every remote-access session requires explicit approval from the target device. Remote access can never start silently.

---

## Architecture

```
app/
├── main.py          ← FastAPI app, CORS, WebSocket endpoint
├── config.py        ← Pydantic settings from .env
├── database.py      ← SQLAlchemy engine + session (SQLite dev / PostgreSQL prod)
├── models/          ← SQLAlchemy ORM models
├── schemas/         ← Pydantic request/response schemas
├── routers/         ← FastAPI routers (auth, devices)
├── websocket/       ← WebSocket connection manager
├── services/        ← Business logic
└── security/        ← JWT + password hashing
```

---

## Quick Start

### 1. Create virtual environment

```bash
cd backend
python -m venv venv

# Windows
venv\Scripts\activate

# Linux / macOS
source venv/bin/activate
```

### 2. Install dependencies

```bash
pip install -r requirements.txt
```

### 3. Configure environment

```bash
cp .env.example .env
# Edit .env — set JWT_SECRET_KEY to a long random string
```

### 4. Run the server

```bash
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

API docs available at: http://localhost:8000/docs

---

## API Reference (Phase 1)

### Authentication

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/auth/register` | Create account, get tokens |
| POST | `/auth/login` | Login, get tokens |
| POST | `/auth/refresh` | Exchange refresh token |
| POST | `/auth/logout` | Client-side token discard |
| GET | `/auth/me` | Current user info |

### Devices

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/devices/register` | Register/update device |
| GET | `/devices/me` | List my devices |
| GET | `/devices/{id}` | Look up a device |
| PATCH | `/devices/{id}/status` | Heartbeat / presence |
| POST | `/devices/fcm-token` | Store FCM token (Phase 3) |

### WebSocket

```
WS /ws/device/{device_id}?token=<access_token>
```

---

## Running Tests

```bash
pytest tests/ -v
```

---

## Database

**Development**: SQLite (`remote_access.db` created automatically)

**Production**: Set `DATABASE_URL=postgresql://user:pass@host/db` in `.env`.
Run Alembic migrations: `alembic upgrade head`

---

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DATABASE_URL` | `sqlite:///./remote_access.db` | DB connection string |
| `JWT_SECRET_KEY` | ⚠️ CHANGE_ME | Secret for JWT signing |
| `JWT_ACCESS_TOKEN_EXPIRE_MINUTES` | `30` | Access token TTL |
| `JWT_REFRESH_TOKEN_EXPIRE_DAYS` | `30` | Refresh token TTL |
| `ALLOWED_ORIGINS` | `http://localhost:3000` | CORS origins |
| `ACCESS_REQUEST_EXPIRE_SECONDS` | `120` | Access request TTL |

---

## Security Notes

- Passwords are bcrypt-hashed; never stored in plaintext.
- JWTs are signed with HS256. Use RS256 in high-security production environments.
- An 8-digit Device ID alone **never** authorizes remote access.
- All endpoints except `/health` require authentication.
- Rate limiting: 200 req/min per IP.

---

## Phase Roadmap

| Phase | Features |
|-------|----------|
| 1 ✅ | Device registration, auth, presence |
| 2 | Pairing system |
| 3 | Access requests, FCM, WebSocket signaling |
| 4 | MediaProjection, WebRTC screen sharing |
| 5 | AccessibilityService, remote control |
| 6 | PostgreSQL, Docker, CI/CD, security hardening |
