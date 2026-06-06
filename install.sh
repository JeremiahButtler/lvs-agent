#!/usr/bin/env bash
# LVS Agent installer
# One-line install: curl --proto '=https' --tlsv1.2 -fsSL https://raw.githubusercontent.com/JeremiahButtler/lvs-agent/main/install.sh | sudo bash
# Copyright © 2026 AideaMaker LLC

set -e

INSTALL_DIR="/opt/lvs-agent"
SERVICE_NAME="lvs-agent"
SERVICE_USER="lvs-agent"
GITHUB_RAW="https://raw.githubusercontent.com/JeremiahButtler/lvs-agent/main"
LOG_FILE="/var/log/lvs-agent.log"

# ── Must run as root ──────────────────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This installer must be run as root (use sudo)." >&2
    exit 1
fi

echo ""
echo "=== LVS Agent Installer ==="
echo ""

# ── Detect distro and install prerequisites ───────────────────────────────────
install_prerequisites() {
    if command -v apt-get &>/dev/null; then
        echo "[1/6] Detected apt-based system (Debian/Ubuntu)…"
        apt-get update -qq
        apt-get install -y -qq python3 curl
    elif command -v dnf &>/dev/null; then
        echo "[1/6] Detected dnf-based system (RHEL/Fedora/CentOS 8+)…"
        dnf install -y -q python3 curl
    elif command -v yum &>/dev/null; then
        echo "[1/6] Detected yum-based system (CentOS/RHEL 7)…"
        yum install -y -q python3 curl
    elif command -v apk &>/dev/null; then
        echo "[1/6] Detected apk-based system (Alpine)…"
        apk add --quiet python3 curl
    else
        echo "ERROR: Unsupported distro — no apt-get, dnf, yum, or apk found." >&2
        exit 1
    fi
}

install_prerequisites

# ── Create unprivileged service user ─────────────────────────────────────────
echo "[2/6] Creating service user '${SERVICE_USER}'…"
useradd --system --no-create-home --shell /sbin/nologin "${SERVICE_USER}" 2>/dev/null || true
# 'already exists' is fine — || true suppresses that non-error

# ── Create install directory (owned by service user) ─────────────────────────
echo "[3/6] Creating ${INSTALL_DIR}…"
mkdir -p "${INSTALL_DIR}"
chown "${SERVICE_USER}:${SERVICE_USER}" "${INSTALL_DIR}"
chmod 750 "${INSTALL_DIR}"

# ── Download agent files ──────────────────────────────────────────────────────
# --proto '=https' --tlsv1.2: enforce HTTPS + modern TLS, reject plain-HTTP and downgrade attacks
echo "[4/6] Downloading agent files…"
curl --proto '=https' --tlsv1.2 -fsSL "${GITHUB_RAW}/agent.py" -o "${INSTALL_DIR}/agent.py"
curl --proto '=https' --tlsv1.2 -fsSL "${GITHUB_RAW}/lvs-agent.service" -o "${INSTALL_DIR}/lvs-agent.service"
chown "${SERVICE_USER}:${SERVICE_USER}" "${INSTALL_DIR}/agent.py"
chmod 750 "${INSTALL_DIR}/agent.py"

# ── Prompt for configuration ──────────────────────────────────────────────────
echo ""
echo "=== Configuration ==="
echo ""

read -rp "LVS server URL [https://www.licenseverificationserver.com]: " LVS_URL
LVS_URL="${LVS_URL:-https://www.licenseverificationserver.com}"

read -rp "License key: " LICENSE_KEY
while [ -z "${LICENSE_KEY}" ]; do
    echo "  License key is required."
    read -rp "License key: " LICENSE_KEY
done

read -rp "Local port [8788]: " PORT
PORT="${PORT:-8788}"

# Validate port is numeric
if ! [[ "${PORT}" =~ ^[0-9]+$ ]]; then
    echo "WARNING: Invalid port '${PORT}' — using default 8788." >&2
    PORT=8788
fi

# ── Generate local bearer token ───────────────────────────────────────────────
# This token authenticates your site backend to the agent.
# Without it, any local process on the server could consume seats or trigger billing.
LOCAL_TOKEN=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))")

# ── Write config.json ─────────────────────────────────────────────────────────
echo "[5/6] Writing configuration…"
CONFIG_FILE="${INSTALL_DIR}/config.json"
cat > "${CONFIG_FILE}" <<EOF
{
  "license_key": "${LICENSE_KEY}",
  "lvs_url": "${LVS_URL}",
  "port": ${PORT},
  "offline_grace_seconds": 86400,
  "local_token": "${LOCAL_TOKEN}"
}
EOF
chown "${SERVICE_USER}:${SERVICE_USER}" "${CONFIG_FILE}"
chmod 600 "${CONFIG_FILE}"
echo "  Config written to ${CONFIG_FILE} (mode 600, ${SERVICE_USER}-readable only)."

# ── Touch log file ────────────────────────────────────────────────────────────
touch "${LOG_FILE}"
chown "${SERVICE_USER}:${SERVICE_USER}" "${LOG_FILE}"
chmod 640 "${LOG_FILE}"

# ── Install and start systemd service ────────────────────────────────────────
echo "[6/6] Installing and starting systemd service…"
cp "${INSTALL_DIR}/lvs-agent.service" "/etc/systemd/system/${SERVICE_NAME}.service"
systemctl daemon-reload
systemctl enable "${SERVICE_NAME}"
systemctl start "${SERVICE_NAME}"

# ── Verify ────────────────────────────────────────────────────────────────────
echo ""
sleep 1
if systemctl is-active --quiet "${SERVICE_NAME}"; then
    echo "=== LVS Agent installed and running! ==="
else
    echo "WARNING: Service may not have started. Check: journalctl -u lvs-agent -n 20" >&2
fi

# ── Print the local token — save this immediately ────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " IMPORTANT — add this to your site's environment or secrets manager:"
echo ""
echo "   LVS_LOCAL_TOKEN=${LOCAL_TOKEN}"
echo ""
echo " Your backend must send:  Authorization: Bearer <token>"
echo " on every request to the agent (except GET /health)."
echo " Integration snippets: https://github.com/JeremiahButtler/lvs-agent/tree/main/snippets"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Health check (no token needed):"
echo "  curl -s http://127.0.0.1:${PORT}/health"
echo ""
echo "Full authorization test:"
echo "  curl -s -X POST http://127.0.0.1:${PORT}/authorize \\"
echo "    -H 'Authorization: Bearer ${LOCAL_TOKEN}' \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -d '{\"external_user_id\": \"test-user-1\"}'"
echo ""
