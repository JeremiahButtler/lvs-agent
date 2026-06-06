# LVS Agent — Feature List

A self-hosted per-user license verification agent for Linux servers. Third-party
site owners install it once and call a local HTTP API to enforce LVS licensing
for their own end-users — no LVS SDK required.

---

## Installation

- **One-line installer** handles all prerequisites automatically:
  ```bash
  curl -sSL https://raw.githubusercontent.com/JeremiahButtler/lvs-agent/main/install.sh | sudo bash
  ```
- **Distro-aware**: detects and uses the correct package manager
  - `apt-get` — Debian, Ubuntu
  - `dnf` — Fedora, RHEL 8+, CentOS Stream
  - `yum` — CentOS 7, RHEL 7
  - `apk` — Alpine Linux
- Installs Python 3 and pip automatically if not present
- Prompts for LVS URL, license key, and local port — no manual file editing needed
- Config written to `/opt/lvs-agent/config.json` (mode 600, root-readable only)
- **Clean uninstaller** removes service, config, and cached data: `sudo bash uninstall.sh`

---

## Core Agent

- **Local HTTP API** on `127.0.0.1:8788` — language-agnostic, any backend can call it
- Binds to localhost only (never `0.0.0.0`) — no external exposure
- No authentication on the local API by design — protected by localhost scope

### Endpoints

| Endpoint | Method | Description |
|---|---|---|
| `/authorize` | POST | Grant or reject a user; returns status + grant token |
| `/revoke` | POST | Revoke a user's grant at LVS and clear local cache |
| `/status` | GET | LVS license info + agent metadata (version, cache count) |
| `/health` | GET | Immediate liveness check; no LVS call (for load balancers) |

---

## Caching & Offline Grace

- **SQLite grant cache** at `/opt/lvs-agent/grants.db` — fast local lookup on repeat requests
- **Offline grace window** (default 24 hours, configurable): if LVS is temporarily
  unreachable, users with a recent cached grant are still authorized
- Cache cleared automatically on revoke or rejection
- Cache served first on every authorize request — minimizes LVS round-trips

---

## Operations

- Runs as a **systemd service** (`lvs-agent.service`): starts on boot, auto-restarts on crash
- Logs to `/var/log/lvs-agent.log` — rotates at 10 MB, keeps 3 archives
- Also logs to journald: `journalctl -u lvs-agent -f`
- Configuration file: `/opt/lvs-agent/config.json`

---

## Integration Snippets

Ready-to-use integration code in `snippets/`:

- **PHP** (`php_example.php`) — `lvs_authorize()` via cURL
- **Python** (`python_example.py`) — `lvs_authorize()` via requests
- **Node.js** (`node_example.js`) — `lvsAuthorize()` using built-in `http`
- **nginx** (`nginx_auth.conf`) — `auth_request` config for transparent HTTP-layer gating

---

Copyright © 2026 AideaMaker LLC
