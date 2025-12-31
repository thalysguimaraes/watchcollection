from slowapi import Limiter
from slowapi.util import get_remote_address
from fastapi import Request


def get_rate_limit_key(request: Request) -> str:
    user = getattr(request.state, "user", None)
    if user:
        return f"user:{user.get('id', 'unknown')}"
    return get_remote_address(request)


limiter = Limiter(key_func=get_rate_limit_key)
