# Project Log — LVS Agent

## Resume Brief

| Field | Detail |
|---|---|
| **What it is** | A public Linux agent package that third-party client websites install to enforce LVS per-user licensing. The agent exposes a local HTTP API (`POST /authorize`, `POST /revoke`, `GET /status`, `GET /health`) that the site's backend calls on localhost. It handles all LVS communication, grant-token caching, offline grace, and license key storage. |
| **Status** | v1.0.0 — initial implementation complete. |
| **Install** | One-line: `curl -sSL https://raw.githubusercontent.com/JeremiahButtler/lvs-agent/main/install.sh \| sudo bash` — or clone the repo and run `sudo bash install.sh`. |
| **Architecture** | `agent.py` — Python 3 asyncio HTTP server (stdlib + optional `requests`); `install.sh` — distro-detecting one-line installer (apt/dnf/yum/apk); `lvs-agent.service` — systemd unit; `snippets/` — PHP, Python, Node.js, nginx integration examples. Config at `/opt/lvs-agent/config.json` (mode 600). Grant cache SQLite at `/opt/lvs-agent/grants.db`. |
| **Repo** | https://github.com/JeremiahButtler/lvs-agent (public) |
| **What's next** | Phase 4: acceptance testing on aideamaker.com + bearlydefares.com. Validate full authorize/revoke/offline-grace flow against live LVS. |

---

## Change History

### 2026-06-05 — Initial implementation: LVS Agent v1.0.0

- **What changed:** Full initial implementation of the LVS Agent daemon.
- **Why:** Third-party client websites needed a standard, installable agent to enforce per-user licensing through LVS without building their own HTTP + caching layer.
- **Details:**
  - `agent.py` — Python 3 stdlib asyncio HTTP server; `/authorize` (cache-first + offline grace), `/revoke`, `/status`, `/health`; SQLite grant cache; rotating log at `/var/log/lvs-agent.log`; binds to `127.0.0.1` only.
  - `install.sh` — distro-detecting installer (apt/dnf/yum/apk); installs Python 3 + pip + requests; prompts for LVS URL, license key, port; writes config.json (mode 600); enables and starts systemd service.
  - `uninstall.sh` — stops/disables service, removes `/opt/lvs-agent/`, removes systemd unit.
  - `lvs-agent.service` — systemd unit template.
  - `snippets/php_example.php`, `snippets/python_example.py`, `snippets/node_example.js`, `snippets/nginx_auth.conf` — integration examples.
  - `FEATURES.md`, `CREDITS.md`, `PROJECT_LOG.md`, `project-log.html` — project documentation.
- **Files created:** All files — initial commit.
