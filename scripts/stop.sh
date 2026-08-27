#!/usr/bin/env bash
# scripts/stop.sh — detiene el agente (systemd si esta disponible, sino mata el binario).
set -uo pipefail
if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files | grep -q agent-browser-use-cloud.service; then
  echo "[*] systemctl stop agent-browser-use-cloud"
  systemctl stop agent-browser-use-cloud
else
  echo "[*] matando picoclaw ..."
  pkill -f "$(command -v picoclaw || echo picoclaw)" || true
  pkill -f go-harnessless || true
  rm -f "${HARNESSLESS_SOCK:-/tmp/harnessless.sock}"
  echo "[ok] detenido (socket eliminado)."
fi
