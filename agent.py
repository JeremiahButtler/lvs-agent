# LVS Agent — per-user license verification daemon
# Part of the License Verification Server ecosystem
# Author: Jeremiah Buttler

import asyncio
import json
import logging
import logging.handlers
import os
import sqlite3
import time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer
from typing import Any, Dict, Optional
from urllib.error import URLError
from urllib.request import Request, urlopen

# ─── Constants ───────────────────────────────────────────────────────────────

VERSION = "1.0.0"
CONFIG_PATH = "/opt/lvs-agent/config.json"
DB_PATH = "/opt/lvs-agent/grants.db"
LOG_PATH = "/var/log/lvs-agent.log"

DEFAULT_CONFIG = {
    "license_key": "",
    "lvs_url": "https://www.licenseverificationserver.com",
    "port": 8788,
    "offline_grace_seconds": 86400,
}

# ─── Logging ─────────────────────────────────────────────────────────────────

def setup_logging() -> logging.Logger:
    logger = logging.getLogger("lvs-agent")
    logger.setLevel(logging.INFO)

    handler = logging.handlers.RotatingFileHandler(
        LOG_PATH, maxBytes=10 * 1024 * 1024, backupCount=3
    )
    handler.setFormatter(
        logging.Formatter("%(asctime)s %(levelname)s %(message)s")
    )
    logger.addHandler(handler)

    # Also log to stderr so journald captures it
    stderr_handler = logging.StreamHandler()
    stderr_handler.setFormatter(
        logging.Formatter("%(asctime)s %(levelname)s %(message)s")
    )
    logger.addHandler(stderr_handler)

    return logger


logger = setup_logging()

# ─── Config ───────────────────────────────────────────────────────────────────

def load_config() -> Dict[str, Any]:
    try:
        with open(CONFIG_PATH, "r") as f:
            data = json.load(f)
        config = {**DEFAULT_CONFIG, **data}
        return config
    except FileNotFoundError:
        logger.error("Config file not found at %s — using defaults", CONFIG_PATH)
        return dict(DEFAULT_CONFIG)
    except json.JSONDecodeError as e:
        logger.error("Config parse error: %s — using defaults", e)
        return dict(DEFAULT_CONFIG)


CONFIG: Dict[str, Any] = load_config()

# ─── Grant cache (SQLite) ─────────────────────────────────────────────────────

def _get_db() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    return conn


def init_db() -> None:
    conn = _get_db()
    conn.execute(
        """CREATE TABLE IF NOT EXISTS grants (
            license_key      TEXT NOT NULL,
            external_user_id TEXT NOT NULL,
            grant_token      TEXT,
            expires_at       INTEGER,
            cached_at        INTEGER,
            PRIMARY KEY (license_key, external_user_id)
        )"""
    )
    conn.commit()
    conn.close()
    logger.info("Grant cache database ready at %s", DB_PATH)


def cache_get(license_key: str, user_id: str) -> Optional[sqlite3.Row]:
    """Return the cached row for this user, or None."""
    conn = _get_db()
    row = conn.execute(
        "SELECT * FROM grants WHERE license_key=? AND external_user_id=?",
        (license_key, user_id),
    ).fetchone()
    conn.close()
    return row


def cache_put(license_key: str, user_id: str, grant_token: str, expires_at: int) -> None:
    conn = _get_db()
    conn.execute(
        """INSERT INTO grants (license_key, external_user_id, grant_token, expires_at, cached_at)
           VALUES (?, ?, ?, ?, ?)
           ON CONFLICT(license_key, external_user_id) DO UPDATE SET
               grant_token=excluded.grant_token,
               expires_at=excluded.expires_at,
               cached_at=excluded.cached_at""",
        (license_key, user_id, grant_token, expires_at, int(time.time())),
    )
    conn.commit()
    conn.close()


def cache_delete(license_key: str, user_id: str) -> None:
    conn = _get_db()
    conn.execute(
        "DELETE FROM grants WHERE license_key=? AND external_user_id=?",
        (license_key, user_id),
    )
    conn.commit()
    conn.close()


def cache_count() -> int:
    conn = _get_db()
    n = conn.execute("SELECT COUNT(*) FROM grants").fetchone()[0]
    conn.close()
    return n

# ─── LVS HTTP helpers ─────────────────────────────────────────────────────────

def _lvs_post(path: str, payload: Dict[str, Any]) -> Dict[str, Any]:
    """POST to LVS and return the parsed JSON response. Raises on network error."""
    lvs_url = CONFIG.get("lvs_url", DEFAULT_CONFIG["lvs_url"]).rstrip("/")
    url = f"{lvs_url}{path}"
    body = json.dumps(payload).encode("utf-8")
    req = Request(url, data=body, headers={"Content-Type": "application/json"})
    with urlopen(req, timeout=8) as resp:
        return json.loads(resp.read().decode("utf-8"))


def _lvs_get(path: str) -> Dict[str, Any]:
    """GET from LVS and return the parsed JSON response. Raises on network error."""
    lvs_url = CONFIG.get("lvs_url", DEFAULT_CONFIG["lvs_url"]).rstrip("/")
    url = f"{lvs_url}{path}"
    req = Request(url, headers={"Accept": "application/json"})
    with urlopen(req, timeout=8) as resp:
        return json.loads(resp.read().decode("utf-8"))


def _parse_expires_at(value: Any) -> int:
    """Convert an expires_at value (ISO string or Unix int) to a Unix timestamp int."""
    if isinstance(value, (int, float)):
        return int(value)
    if isinstance(value, str):
        try:
            dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
            return int(dt.timestamp())
        except ValueError:
            pass
    # Fallback: 24 hours from now
    return int(time.time()) + 86400

# ─── Endpoint handlers ───────────────────────────────────────────────────────

def handle_authorize(request_body: bytes) -> Dict[str, Any]:
    """POST /authorize — check cache, then call LVS."""
    try:
        data = json.loads(request_body.decode("utf-8"))
    except (json.JSONDecodeError, UnicodeDecodeError):
        return {"status": "error", "reason": "invalid_json"}

    user_id = str(data.get("external_user_id", "")).strip()
    kind = str(data.get("kind", "user"))
    display = data.get("display")

    if not user_id:
        return {"status": "error", "reason": "missing_external_user_id"}

    license_key = CONFIG.get("license_key", "")
    now = int(time.time())

    # Step 1: Check live cache (not expired)
    row = cache_get(license_key, user_id)
    if row and row["expires_at"] and row["expires_at"] > now:
        return {
            "status": "granted",
            "cached": True,
            "grant_token": row["grant_token"],
            "expires_at": datetime.fromtimestamp(row["expires_at"], tz=timezone.utc).isoformat(),
        }

    # Step 2: Call LVS
    try:
        payload: Dict[str, Any] = {
            "license_key": license_key,
            "external_user_id": user_id,
            "kind": kind,
        }
        if display is not None:
            payload["display"] = display

        result = _lvs_post("/api/v1/license/users/authorize", payload)

        if result.get("status") == "granted":
            expires_at_ts = _parse_expires_at(result.get("expires_at", 0))
            cache_put(license_key, user_id, result.get("grant_token", ""), expires_at_ts)
            logger.info("Authorized user %s (live)", user_id)
        else:
            # Rejected — clear any stale cache
            cache_delete(license_key, user_id)
            logger.info("Rejected user %s: %s", user_id, result.get("reason", "unknown"))

        return result

    except (URLError, OSError, Exception) as e:
        logger.warning("LVS unreachable: %s — checking offline cache for %s", e, user_id)

        # Step 5: Offline fallback — check cache ignoring expiry, within grace window
        grace = int(CONFIG.get("offline_grace_seconds", 86400))
        row = cache_get(license_key, user_id)
        if row and row["cached_at"] and (now - row["cached_at"]) <= grace:
            logger.info("Offline grant for user %s (cached %ds ago)", user_id, now - row["cached_at"])
            return {
                "status": "granted",
                "cached": True,
                "expires_at": datetime.fromtimestamp(row["expires_at"], tz=timezone.utc).isoformat()
                if row["expires_at"]
                else None,
            }

        logger.warning("No valid cache entry for user %s during LVS outage", user_id)
        return {"status": "error", "reason": "lvs_unreachable"}


def handle_revoke(request_body: bytes) -> Dict[str, Any]:
    """POST /revoke — revoke a user grant at LVS and clear local cache."""
    try:
        data = json.loads(request_body.decode("utf-8"))
    except (json.JSONDecodeError, UnicodeDecodeError):
        return {"status": "error", "reason": "invalid_json"}

    user_id = str(data.get("external_user_id", "")).strip()
    if not user_id:
        return {"status": "error", "reason": "missing_external_user_id"}

    license_key = CONFIG.get("license_key", "")

    try:
        result = _lvs_post(
            "/api/v1/license/users/revoke",
            {"license_key": license_key, "external_user_id": user_id},
        )
        cache_delete(license_key, user_id)
        logger.info("Revoked user %s", user_id)
        return {"status": "revoked"}
    except Exception as e:
        logger.error("Revoke failed for user %s: %s", user_id, e)
        # Still clear local cache even if LVS call failed
        cache_delete(license_key, user_id)
        return {"status": "error", "reason": str(e)}


def handle_status() -> Dict[str, Any]:
    """GET /status — return LVS license info plus local agent metadata."""
    license_key = CONFIG.get("license_key", "")
    base = {
        "agent_version": VERSION,
        "cache_entries": cache_count(),
    }

    try:
        lvs_data = _lvs_get(f"/api/v1/license/users?license_key={license_key}")
        return {**lvs_data, **base}
    except Exception as e:
        logger.warning("LVS unreachable for /status: %s", e)
        return {
            **base,
            "status": "error",
            "reason": "lvs_unreachable",
            "detail": str(e),
        }


def handle_health() -> Dict[str, Any]:
    """GET /health — immediate response, no LVS call."""
    return {"status": "ok", "version": VERSION}

# ─── HTTP server ──────────────────────────────────────────────────────────────

class AgentHandler(BaseHTTPRequestHandler):
    """Minimal synchronous HTTP handler — good enough for localhost-only traffic."""

    def log_message(self, format: str, *args: Any) -> None:  # noqa: A002
        # Route access logs through our logger instead of stderr
        logger.info("HTTP %s %s", self.address_string(), format % args)

    def _send_json(self, data: Dict[str, Any], status: int = 200) -> None:
        body = json.dumps(data).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _read_body(self) -> bytes:
        length = int(self.headers.get("Content-Length", 0))
        return self.rfile.read(length) if length > 0 else b""

    def do_POST(self) -> None:
        body = self._read_body()
        if self.path == "/authorize":
            result = handle_authorize(body)
            self._send_json(result)
        elif self.path == "/revoke":
            result = handle_revoke(body)
            self._send_json(result)
        else:
            self._send_json({"status": "error", "reason": "not_found"}, status=404)

    def do_GET(self) -> None:
        if self.path == "/status":
            self._send_json(handle_status())
        elif self.path == "/health":
            self._send_json(handle_health())
        else:
            self._send_json({"status": "error", "reason": "not_found"}, status=404)

# ─── Entry point ──────────────────────────────────────────────────────────────

def main() -> None:
    init_db()
    port = int(CONFIG.get("port", 8788))

    # Security: always bind to localhost only — never 0.0.0.0
    host = "127.0.0.1"
    server = HTTPServer((host, port), AgentHandler)
    logger.info("LVS Agent v%s listening on %s:%d", VERSION, host, port)
    logger.info(
        "Security note: bound to localhost only — no external access. "
        "No authentication required for local callers by design."
    )

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        logger.info("LVS Agent shutting down")
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
