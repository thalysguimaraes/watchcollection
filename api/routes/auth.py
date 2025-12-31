import os
import uuid
import secrets
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, HTTPException, Depends, Request
from pydantic import BaseModel, EmailStr

from auth import (
    create_access_token,
    create_refresh_token,
    create_entitlement_token,
    verify_token,
    get_current_user,
)

router = APIRouter(prefix="/auth", tags=["auth"])

_magic_link_tokens: dict[str, dict] = {}
_users_store: dict[str, dict] = {}


class MagicLinkRequest(BaseModel):
    email: EmailStr


class MagicLinkResponse(BaseModel):
    message: str
    token: Optional[str] = None


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int


class RefreshRequest(BaseModel):
    refresh_token: str


class EntitlementResponse(BaseModel):
    token: str
    entitlement: str
    expires_in: int


class ReceiptRequest(BaseModel):
    receipt_data: str
    platform: str = "ios"


@router.post("/magic-link", response_model=MagicLinkResponse)
async def request_magic_link(request: MagicLinkRequest):
    token = secrets.token_urlsafe(32)
    _magic_link_tokens[token] = {
        "email": request.email,
        "created_at": datetime.utcnow().isoformat(),
    }

    if os.getenv("DEBUG"):
        return MagicLinkResponse(
            message="Magic link sent (dev mode: token included)",
            token=token,
        )

    return MagicLinkResponse(message="Magic link sent to your email")


@router.get("/verify")
async def verify_magic_link(token: str) -> TokenResponse:
    token_data = _magic_link_tokens.pop(token, None)
    if not token_data:
        raise HTTPException(status_code=400, detail="Invalid or expired token")

    email = token_data["email"]

    user = None
    for uid, u in _users_store.items():
        if u["email"] == email:
            user = u
            break

    if not user:
        user_id = str(uuid.uuid4())
        user = {
            "id": user_id,
            "email": email,
            "entitlement": "free",
            "created_at": datetime.utcnow().isoformat(),
        }
        _users_store[user_id] = user
    else:
        user_id = user["id"]

    access_token = create_access_token(user_id, user.get("entitlement", "free"))
    refresh_token = create_refresh_token(user_id)

    return TokenResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        expires_in=3600,
    )


@router.post("/refresh", response_model=TokenResponse)
async def refresh_access_token(request: RefreshRequest):
    payload = verify_token(request.refresh_token, expected_type="refresh")
    user_id = payload["sub"]

    user = _users_store.get(user_id)
    entitlement = user.get("entitlement", "free") if user else "free"

    access_token = create_access_token(user_id, entitlement)
    refresh_token = create_refresh_token(user_id)

    return TokenResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        expires_in=3600,
    )


@router.get("/entitlement", response_model=EntitlementResponse)
async def get_entitlement(user: dict = Depends(get_current_user)):
    token = create_entitlement_token(user["id"], user["entitlement"])
    return EntitlementResponse(
        token=token,
        entitlement=user["entitlement"],
        expires_in=3600,
    )


@router.post("/verify-receipt")
async def verify_receipt(
    request: ReceiptRequest,
    user: dict = Depends(get_current_user),
):
    if user["id"] in _users_store:
        _users_store[user["id"]]["entitlement"] = "pro"

    return {
        "status": "success",
        "entitlement": "pro",
        "message": "Receipt verified (stub implementation)",
    }


@router.get("/me")
async def get_me(user: dict = Depends(get_current_user)):
    stored = _users_store.get(user["id"])
    if stored:
        return stored
    return user
