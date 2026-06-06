#!/usr/bin/env bash
# LVS Agent uninstaller
# Copyright © 2026 AideaMaker LLC

set -e

SERVICE_NAME="lvs-agent"
INSTALL_DIR="/opt/lvs-agent"

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This uninstaller must be run as root (use sudo)." >&2
    exit 1
fi

echo ""
echo "=== LVS Agent Uninstaller ==="
echo ""

# Stop and disable the service
if systemctl is-active --quiet "${SERVICE_NAME}" 2>/dev/null; then
    echo "Stopping ${SERVICE_NAME} service…"
    systemctl stop "${SERVICE_NAME}"
fi

if systemctl is-enabled --quiet "${SERVICE_NAME}" 2>/dev/null; then
    echo "Disabling ${SERVICE_NAME} service…"
    systemctl disable "${SERVICE_NAME}"
fi

# Remove systemd unit
UNIT_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
if [ -f "${UNIT_FILE}" ]; then
    echo "Removing systemd unit ${UNIT_FILE}…"
    rm -f "${UNIT_FILE}"
fi

# Reload systemd
systemctl daemon-reload
systemctl reset-failed 2>/dev/null || true

# Remove install directory (includes config.json, agent.py, grants.db)
if [ -d "${INSTALL_DIR}" ]; then
    echo "Removing ${INSTALL_DIR}…"
    rm -rf "${INSTALL_DIR}"
fi

echo ""
echo "LVS Agent has been removed."
echo ""
echo "Note: /var/log/lvs-agent.log was left in place."
echo "Remove it manually if desired: rm -f /var/log/lvs-agent.log"
echo ""
