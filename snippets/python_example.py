import os

import requests

# Set LVS_LOCAL_TOKEN in your environment (from /opt/lvs-agent/config.json)
LVS_LOCAL_TOKEN = os.getenv("LVS_LOCAL_TOKEN", "")


def lvs_authorize(user_id: str, kind: str = "user") -> bool:
    """Returns True if the user has a valid LVS grant."""
    headers: dict = {"Content-Type": "application/json"}
    if LVS_LOCAL_TOKEN:
        headers["Authorization"] = f"Bearer {LVS_LOCAL_TOKEN}"
    try:
        r = requests.post(
            "http://127.0.0.1:8788/authorize",
            json={"external_user_id": str(user_id), "kind": kind},
            headers=headers,
            timeout=2,
        )
        return r.json().get("status") == "granted"
    except Exception:
        return False  # agent unreachable — fail closed
