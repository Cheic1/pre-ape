"""In-memory sliding-window rate limiter.

Deliberately minimal (single-process, no Redis dependency yet): sufficient for the
/auth endpoints of P1-A1. If the API is ever scaled horizontally the limiter must
move to a shared store (Redis is already a declared dependency).
"""
import ipaddress
import threading
import time
from collections import deque

from app.core.config import settings


def _is_loopback(host: str) -> bool:
    try:
        return ipaddress.ip_address(host).is_loopback
    except ValueError:
        return False


def client_ip(request) -> str:
    """Rate-limit key source: the socket peer, unless it is a loopback proxy (M1).

    Behind cloudflared every request arrives from 127.0.0.1, which would collapse
    all users into one bucket. Only when the peer *is* loopback (trusted proxy) is
    ``CF-Connecting-IP`` honoured — and only if it parses as an IP literal. A
    direct remote peer could spoof that header, so it is ignored for them and the
    key falls back to ``request.client.host``.
    """
    host = request.client.host if request.client else "unknown"
    if not _is_loopback(host):
        return host
    forwarded = (request.headers.get("CF-Connecting-IP") or "").strip()
    if not forwarded:
        return host
    try:
        ipaddress.ip_address(forwarded)
    except ValueError:
        return host
    return forwarded


class SlidingWindowRateLimiter:
    """Allows at most ``max_requests`` per key inside a sliding ``window_seconds``."""

    def __init__(self, max_requests: int, window_seconds: float):
        self.max_requests = max_requests
        self.window_seconds = window_seconds
        self._hits: dict[str, deque[float]] = {}
        self._lock = threading.Lock()

    def allow(self, key: str) -> bool:
        """Record a hit for ``key`` and return True if it is within the limit."""
        now = time.monotonic()
        with self._lock:
            if len(self._hits) > 4096:
                self._prune_idle_keys(now)
            hits = self._hits.get(key)
            if hits is None:
                hits = self._hits[key] = deque()
            cutoff = now - self.window_seconds
            while hits and hits[0] <= cutoff:
                hits.popleft()
            if len(hits) >= self.max_requests:
                return False
            hits.append(now)
            return True

    def reset(self, key: str | None = None) -> None:
        """Forget recorded hits (all, or for a single key). Used by tests."""
        with self._lock:
            if key is None:
                self._hits.clear()
            else:
                self._hits.pop(key, None)

    def _prune_idle_keys(self, now: float) -> None:
        cutoff = now - self.window_seconds
        for key in [k for k, hits in self._hits.items() if not hits or hits[-1] <= cutoff]:
            del self._hits[key]


# Rate limit for POST /api/v1/auth/* (register + login), per client IP.
auth_rate_limiter = SlidingWindowRateLimiter(
    max_requests=settings.AUTH_RATE_LIMIT_PER_MINUTE,
    window_seconds=60.0,
)
