import os
import jwt
from datetime import datetime, timedelta, timezone
from fastapi import HTTPException, Request
from typing import Optional

JWT_SECRET = os.getenv("JWT_SECRET", "dev-secret-change-in-prod")
JWT_ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60
REFRESH_TOKEN_EXPIRE_DAYS = 7


def create_access_token(user_id: str, entitlement: str = "free") -> str:
    expires_at = datetime.now(timezone.utc) + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    payload = {
        "sub": user_id,
        "entitlement": entitlement,
        "iat": datetime.now(timezone.utc),
        "exp": expires_at,
        "type": "access",
    }
    return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)


def create_refresh_token(user_id: str) -> str:
    expires_at = datetime.now(timezone.utc) + timedelta(days=REFRESH_TOKEN_EXPIRE_DAYS)
    payload = {
        "sub": user_id,
        "iat": datetime.now(timezone.utc),
        "exp": expires_at,
        "type": "refresh",
    }
    return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)


def create_entitlement_token(user_id: str, entitlement: str) -> str:
    expires_at = datetime.now(timezone.utc) + timedelta(hours=1)
    payload = {
        "sub": user_id,
        "entitlement": entitlement,
        "iat": datetime.now(timezone.utc),
        "exp": expires_at,
        "type": "entitlement",
    }
    return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)


def verify_token(token: str, expected_type: Optional[str] = None) -> dict:
    try:
        payload = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
        if expected_type and payload.get("type") != expected_type:
            raise HTTPException(status_code=401, detail="Invalid token type")
        return payload
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token has expired")
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=401, detail="Invalid token")


def get_current_user(request: Request) -> dict:
    auth_header = request.headers.get("Authorization")
    if not auth_header or not auth_header.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing or invalid Authorization header")

    token = auth_header.split(" ", 1)[1]
    payload = verify_token(token, expected_type="access")

    user = {
        "id": payload["sub"],
        "entitlement": payload.get("entitlement", "free"),
    }
    request.state.user = user
    return user


def get_optional_user(request: Request) -> Optional[dict]:
    auth_header = request.headers.get("Authorization")
    if not auth_header or not auth_header.startswith("Bearer "):
        return None

    try:
        token = auth_header.split(" ", 1)[1]
        payload = verify_token(token, expected_type="access")
        user = {
            "id": payload["sub"],
            "entitlement": payload.get("entitlement", "free"),
        }
        request.state.user = user
        return user
    except HTTPException:
        return None


def require_pro_user(request: Request) -> dict:
    user = get_current_user(request)
    if user.get("entitlement") != "pro":
        raise HTTPException(status_code=402, detail="Pro subscription required")
    return user
