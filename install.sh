#!/usr/bin/env bash
# LVS Agent installer
# One-line install: curl -sSL https://raw.githubusercontent.com/JeremiahButtler/lvs-agent/main/install.sh | sudo bash
# Copyright © 2026 AideaMaker LLC

set -e

INSTALL_DIR="/opt/lvs-agent"
SERVICE_NAME="lvs-agent"
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
        echo "[1/5] Detected apt-based system (Debian/Ubuntu)…"
        apt-get update -qq
        apt-get install -y -qq python3 python3-pip curl
    elif command -v dnf &>/dev/null; then
        echo "[1/5] Detected dnf-based system (RHEL/Fedora/CentOS 8+)…"
        dnf install -y -q python3 python3-pip curl
    elif command -v yum &>/dev/null; then
        echo "[1/5] Detected yum-based system (CentOS/RHEL 7)…"
        yum install -y -q python3 python3-pip curl
    elif command -v apk &>/dev/null; then
        echo "[1/5] Detected apk-based system (Alpine)…"
        apk add --quiet python3 py3-pip curl
    else
        echo "ERROR: Unsupported distro — no apt-get, dnf, yum, or apk found." >&2
        exit 1
    fi
}

install_prerequisites

# ── Install requests Python package ──────────────────────────────────────────
echo "[2/5] Installing Python 'requests' package…"
pip3 install --quiet requests 2>/dev/null || pip install --quiet requests 2>/dev/null || true
# agent.py falls back to urllib if requests is absent — non-fatal

# ── Create install directory ──────────────────────────────────────────────────
echo "[3/5] Creating ${INSTALL_DIR}…"
mkdir -p "${INSTALL_DIR}"
chmod 755 "${INSTALL_DIR}"

# ── Download agent files ──────────────────────────────────────────────────────
echo "[4/5] Downloading agent files…"
curl -sSL "${GITHUB_RAW}/agent.py" -o "${INSTALL_DIR}/agent.py"
curl -sSL "${GITHUB_RAW}/lvs-agent.service" -o "${INSTALL_DIR}/lvs-agent.service"
chmod 755 "${INSTALL_DIR}/agent.py"

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

# ── Write config.json ─────────────────────────────────────────────────────────
CONFIG_FILE="${INSTALL_DIR}/config.json"
cat > "${CONFIG_FILE}" <<EOF
{
  "license_key": "${LICENSE_KEY}",
  "lvs_url": "${LVS_URL}",
  "port": ${PORT},
  "offline_grace_seconds": 86400
}
EOF
chmod 600 "${CONFIG_FILE}"
chown root:root "${CONFIG_FILE}"
echo "  Config written to ${CONFIG_FILE} (mode 600, root-readable only)."

# ── Touch log file ────────────────────────────────────────────────────────────
touch "${LOG_FILE}"
chmod 640 "${LOG_FILE}"

# ── Install and start systemd service ────────────────────────────────────────
echo "[5/5] Installing and starting systemd service…"
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

echo ""
echo "Test with:"
echo "  curl -s -X POST http://127.0.0.1:${PORT}/health"
echo ""
echo "Integration docs and snippets:"
echo "  https://github.com/JeremiahButtler/lvs-agent"
echo ""
