"""JWT creation, validation, and FastAPI dependency."""

from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError, jwt
from sqlalchemy.orm import Session

from app.config import get_settings
from app.database import get_db

settings = get_settings()
_bearer = HTTPBearer(auto_error=True)

_ACCESS_TYPE = "access"
_REFRESH_TYPE = "refresh"


# ── Token creation ─────────────────────────────────────────────────────────────

def create_access_token(user_id: str) -> str:
    expire = datetime.now(timezone.utc) + timedelta(
        minutes=settings.jwt_access_token_expire_minutes
    )
    payload = {"sub": user_id, "exp": expire, "type": _ACCESS_TYPE}
    return jwt.encode(payload, settings.jwt_secret_key, algorithm=settings.jwt_algorithm)


def create_refresh_token(user_id: str) -> str:
    expire = datetime.now(timezone.utc) + timedelta(
        days=settings.jwt_refresh_token_expire_days
    )
    payload = {"sub": user_id, "exp": expire, "type": _REFRESH_TYPE}
    return jwt.encode(payload, settings.jwt_secret_key, algorithm=settings.jwt_algorithm)


# ── Token validation ───────────────────────────────────────────────────────────

def _decode(token: str, expected_type: str) -> str:
    """Decode *token* and return the subject (user_id). Raises HTTPException on failure."""
    credentials_error = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, settings.jwt_secret_key, algorithms=[settings.jwt_algorithm])
    except JWTError:
        raise credentials_error

    token_type: Optional[str] = payload.get("type")
    user_id: Optional[str] = payload.get("sub")

    if token_type != expected_type or user_id is None:
        raise credentials_error

    return user_id


def decode_access_token(token: str) -> str:
    return _decode(token, _ACCESS_TYPE)


def decode_refresh_token(token: str) -> str:
    return _decode(token, _REFRESH_TYPE)


# ── FastAPI dependency ─────────────────────────────────────────────────────────

def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(_bearer),
    db: Session = Depends(get_db),
):
    """Dependency that returns the authenticated User ORM object."""
    from app.models.user import User  # local import to avoid circular

    user_id = decode_access_token(credentials.credentials)
    user = db.query(User).filter(User.id == user_id, User.is_active == True).first()
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not found or inactive",
        )
    return user
