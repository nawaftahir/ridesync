"""Password hashing and bearer-token helpers for RideSync accounts."""

import hashlib
import hmac
import re
import secrets

from fastapi import Depends, HTTPException, Request, status

from app.db import get_db

_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
TOKEN_LIFETIME_DAYS = 30


def normalize_email(raw_email: str) -> str:
    """Trim, lowercase, and validate an email address."""
    email = raw_email.strip().lower()
    if len(email) > 255 or not _EMAIL_RE.fullmatch(email):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Please enter a valid email address.",
        )
    return email


def hash_password(password: str) -> str:
    """Hash a password with stdlib scrypt and a random 16-byte salt."""
    salt = secrets.token_bytes(16)
    derived = hashlib.scrypt(
        password.encode("utf-8"),
        salt=salt,
        n=16384,
        r=8,
        p=1,
        dklen=32,
    )
    return f"scrypt${salt.hex()}${derived.hex()}"


def verify_password(password: str, stored_hash: str) -> bool:
    """Verify a plaintext password against a stored scrypt hash."""
    if not stored_hash or not stored_hash.startswith("scrypt$"):
        return False
    parts = stored_hash.split("$")
    if len(parts) != 3:
        return False
    try:
        salt = bytes.fromhex(parts[1])
        expected = bytes.fromhex(parts[2])
    except ValueError:
        return False

    derived = hashlib.scrypt(
        password.encode("utf-8"),
        salt=salt,
        n=16384,
        r=8,
        p=1,
        dklen=len(expected),
    )
    return hmac.compare_digest(derived, expected)


def hash_token(raw_token: str) -> str:
    """Return the SHA-256 hex digest stored in auth_tokens."""
    return hashlib.sha256(raw_token.encode("utf-8")).hexdigest()


def create_auth_token(cur, user_id: int) -> str:
    """Issue a new 30-day bearer token and store its hash in MariaDB."""
    raw_token = secrets.token_urlsafe(32)
    token_digest = hash_token(raw_token)
    cur.execute(
        "INSERT INTO auth_tokens (token_hash, user_id, expires_at) "
        "VALUES (%s, %s, DATE_ADD(NOW(), INTERVAL %s DAY))",
        (token_digest, user_id, TOKEN_LIFETIME_DAYS),
    )
    return raw_token


def extract_bearer_token(request: Request) -> str | None:
    """Extract the Bearer token from the Authorization header if present."""
    header = request.headers.get("Authorization")
    if not header:
        return None
    parts = header.strip().split(None, 1)
    if len(parts) != 2 or parts[0].lower() != "bearer" or not parts[1].strip():
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authorization header.",
        )
    return parts[1].strip()


def _lookup_user_by_token(cur, raw_token: str) -> dict:
    token_digest = hash_token(raw_token)
    cur.execute(
        "SELECT u.id, u.email, u.name, u.created_at "
        "FROM auth_tokens t "
        "INNER JOIN users u ON u.id = t.user_id "
        "WHERE t.token_hash = %s AND t.expires_at > NOW()",
        (token_digest,),
    )
    row = cur.fetchone()
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Session expired or invalid. Please log in again.",
        )
    return {
        "id": int(row["id"]),
        "email": str(row["email"] or ""),
        "name": str(row["name"]),
        "created_at": row["created_at"],
    }


def get_optional_user(request: Request, conn=Depends(get_db)) -> dict | None:
    """Return the authenticated user when a Bearer header is sent, else None."""
    raw_token = extract_bearer_token(request)
    if raw_token is None:
        return None
    with conn.cursor() as cur:
        return _lookup_user_by_token(cur, raw_token)


def get_current_user(request: Request, conn=Depends(get_db)) -> dict:
    """Require a valid Bearer token and return the authenticated user."""
    raw_token = extract_bearer_token(request)
    if raw_token is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication required.",
        )
    with conn.cursor() as cur:
        return _lookup_user_by_token(cur, raw_token)
