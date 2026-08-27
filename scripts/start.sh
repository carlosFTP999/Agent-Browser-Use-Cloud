#!/usr/bin/env bash
# scripts/start.sh — arranca el agente (systemd si esta disponible, sino directo).
set -uo pipefail
if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files | grep -q agent-browser-use-cloud.service; then
  echo "[*] systemctl start agent-browser-use-cloud"
  systemctl start agent-browser-use-cloud
else
  ENV_FILE="${ENV_FILE:-.env}"
  [ -f "$ENV_FILE" ] && set -a && . "$ENV_FILE" && set +a
  BIN="${PICOCLAW_BIN:-${INSTALL_BIN:-/usr/local/bin}/picoclaw}"
  echo "[*] ejecucion directa: $BIN (logs en logs/) "
  mkdir -p logs
  exec "$BIN" >>logs/agent.out.log 2>&1
fi
