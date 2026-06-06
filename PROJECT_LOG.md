# Project Log — LVS Agent

## Resume Brief

| Field | Detail |
|---|---|
| **What it is** | A public Linux agent package that third-party client websites install to enforce LVS per-user licensing. The agent exposes a local HTTP API (`POST /authorize`, `POST /revoke`, `GET /status`, `GET /health`) that the site's backend calls on localhost. It handles all LVS communication, grant-token caching, offline grace, and license key storage. |
| **Status** | v1.2.0 — file-integrity hash reporting added. Agent computes SHA-256 of its own source at startup and sends `X-Agent-Version` + `X-Agent-Hash` headers on every outbound LVS authorize/revoke request. |
| **Install** | One-line: `curl --proto '=https' --tlsv1.2 -fsSL https://raw.githubusercontent.com/JeremiahButtler/lvs-agent/main/install.sh \| sudo bash` — or clone the repo and run `sudo bash install.sh`. |
| **Architecture** | `agent.py` — Python 3 `ThreadingHTTPServer` (stdlib-only); bearer-token auth (`local_token`); 200/403/503 status codes; HTTPS enforcement. `install.sh` — distro-detecting installer (apt/dnf/yum/apk); creates `lvs-agent` system user; generates `local_token`. `lvs-agent.service` — systemd unit with full hardening (NoNewPrivileges, ProtectSystem, PrivateTmp). `snippets/` — PHP, Python, Node.js, nginx examples (all pass `Authorization: Bearer <token>`). Config at `/opt/lvs-agent/config.json` (mode 600, owned by `lvs-agent`). Grant cache SQLite at `/opt/lvs-agent/grants.db`. |
| **Repo** | https://github.com/JeremiahButtler/lvs-agent (public) |
| **What's next** | LVS server-side: parse and log `X-Agent-Version` / `X-Agent-Hash` headers from agent requests for integrity dashboarding. Build integration documentation page on the LVS website (detailed install guide for client users, design-review guided). Phase 4: acceptance testing on aideamaker.com + bearlydefares.com. Validate full authorize/revoke/offline-grace flow against live LVS. |

---

## Change History

### 2026-06-05 — v1.2.0: File-integrity hash reporting

- **What changed:** Agent computes SHA-256 of its own source file (`agent.py`) at startup and sends `X-Agent-Version` and `X-Agent-Hash` headers on every outbound authorize and revoke request to the LVS server.
- **Why:** Allows the LVS server to detect unauthorized modifications or file tampering on client deployments by comparing the reported hash against the known-good hash for that version.
- **Details:**
  - `import hashlib` added to stdlib imports.
  - `AGENT_HASH` computed at module level via `hashlib.sha256(open(__file__, "rb").read()).hexdigest()` with a safe fallback of `"unknown"` on any exception.
  - `VERSION` bumped from `1.1.0` to `1.2.0`.
  - `_lvs_post()` headers dict extended with `"X-Agent-Version": VERSION` and `"X-Agent-Hash": AGENT_HASH`. These headers go outbound to LVS only — the incoming local HTTP handler is unchanged.
- **Files touched:** `agent.py`, `PROJECT_LOG.md`, `project-log.html`.

### 2026-06-05 — Security hardening: v1.1.0

- **What changed:** Six security vulnerabilities addressed; agent bumped to v1.1.0.
- **Why:** The agent was running as root with no local auth — any process on the client server could trigger paid billing upgrades, revoke legitimate users, or leak user IDs. The nginx integration also silently failed open, allowing unlicensed users through regardless of licensing status.
- **Details:**
  - **H1 — Local API auth (shared-secret bearer token):** Installer generates a random `local_token` (stored in `config.json` 600); every request except `GET /health` requires `Authorization: Bearer <token>`. Prevents unauthorized seat consumption and billing triggers from other local processes.
  - **H2 — Drop root + systemd hardening:** Service now runs as dedicated system user `lvs-agent` (no shell, no home directory). Unit adds `NoNewPrivileges=yes`, `ProtectSystem=strict`, `ProtectHome=yes`, `PrivateTmp=yes`, `CapabilityBoundingSet=`, `AmbientCapabilities=`.
  - **H3 — Correct HTTP status codes (fix nginx fail-open):** Agent returns 200 granted / 403 rejected / 503 unreachable. Previously the agent returned 200 for both granted and rejected; since nginx `auth_request` only reads the status code, all users (including over-limit) were silently allowed through.
  - **M4 — HTTPS enforcement:** Agent refuses to start if `lvs_url` is non-HTTPS and non-localhost. Passes explicit `ssl.create_default_context()` to `urlopen` (verified TLS, not implicit).
  - **M6 — Request size cap + ThreadingHTTPServer:** Body capped at 64 KB (local DoS prevention). Server switched from single-threaded `HTTPServer` to `ThreadingHTTPServer` so a slow LVS call doesn't block other requests.
  - **L7 — Narrowed exception catch:** `except Exception` replaced with `except (URLError, OSError, TimeoutError)` for the offline-fallback path. A bad LVS response (`json.JSONDecodeError`) now returns `lvs_bad_response` rather than wrongly triggering offline grant.
  - **L8 — Input validation:** `kind` whitelisted to `{"user","seat","device"}`; `external_user_id` and `display` capped at 256 chars.
  - **L9 — Installer hardening:** `curl` flags changed to `--proto '=https' --tlsv1.2 -fsSL`. Installer creates `lvs-agent` system user, sets correct ownership on all files. Token is printed prominently after install for the operator to save.
  - **L10 — Dead import removed:** `import asyncio` (unused) removed.
  - All four client snippets updated: pass `Authorization: Bearer` header from `LVS_LOCAL_TOKEN` env var.
- **Files touched:** `agent.py`, `lvs-agent.service`, `install.sh`, `snippets/nginx_auth.conf`, `snippets/php_example.php`, `snippets/python_example.py`, `snippets/node_example.js`.

### 2026-06-05 — Initial implementation: LVS Agent v1.0.0

- **What changed:** Full initial implementation of the LVS Agent daemon.
- **Why:** Third-party client websites needed a standard, installable agent to enforce per-user licensing through LVS without building their own HTTP + caching layer.
- **Details:**
  - `agent.py` — Python 3 stdlib HTTP server; `/authorize` (cache-first + offline grace), `/revoke`, `/status`, `/health`; SQLite grant cache; rotating log at `/var/log/lvs-agent.log`; binds to `127.0.0.1` only.
  - `install.sh` — distro-detecting installer (apt/dnf/yum/apk); installs Python 3 + pip + requests; prompts for LVS URL, license key, port; writes config.json (mode 600); enables and starts systemd service.
  - `uninstall.sh` — stops/disables service, removes `/opt/lvs-agent/`, removes systemd unit.
  - `lvs-agent.service` — systemd unit template.
  - `snippets/php_example.php`, `snippets/python_example.py`, `snippets/node_example.js`, `snippets/nginx_auth.conf` — integration examples.
  - `FEATURES.md`, `CREDITS.md`, `PROJECT_LOG.md`, `project-log.html` — project documentation.
- **Files created:** All files — initial commit.
