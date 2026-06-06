import requests


def lvs_authorize(user_id: str, kind: str = "user") -> bool:
    """Returns True if the user has a valid LVS grant."""
    try:
        r = requests.post(
            "http://127.0.0.1:8788/authorize",
            json={"external_user_id": str(user_id), "kind": kind},
            timeout=2,
        )
        return r.json().get("status") == "granted"
    except Exception:
        return False  # agent unreachable — fail closed
