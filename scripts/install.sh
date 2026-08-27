#!/usr/bin/env bash
# scripts/install.sh — instalación idempotente del agente en VPS free tier.
# Principios: sin Python en prod, binarios Go estaticos, $0 asumido.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$REPO_DIR/build}"
INSTALL_BIN="${INSTALL_BIN:-/usr/local/bin}"
USE_SYSTEMD=true
[ "$(id -u)" -eq 0 ] || { echo "[warn] no root: binarios quedan en $REPO_DIR/bin y se omite systemd"; INSTALL_BIN="$REPO_DIR/bin"; USE_SYSTEMD=false; mkdir -p "$INSTALL_BIN"; }

GO_VERSION="${GO_VERSION:-1.25.0}"
ARCH="$(uname -m)"; case "$ARCH" in x86_64) GOARCH=amd64;; aarch64|arm64) GOARCH=arm64;; *) GOARCH=amd64;; esac
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"

# Pin de commit de PicoClaw — DEBE FIJARSE (es <v1.0, API inestable).
PIN_COMMIT_PICOCLAW="${PIN_COMMIT_PICOCLAW:-<PIN_COMMIT_PICOCLAW>}"
PICOCLAW_REPO="https://github.com/sipeed/picoclaw"
HARNESSLESS_REPO="https://github.com/browser-use/go-harnessless"

echo "[*] REPO_DIR=$REPO_DIR  BUILD_DIR=$BUILD_DIR  INSTALL_BIN=$INSTALL_BIN"

# --- 1. Prereqs: curl / jq (sin python) ---
for c in curl jq; do command -v "$c" >/dev/null 2>&1 || { echo "[fatal] falta '$c' (instala con apt-get install -y curl jq)"; exit 1; }; done

# --- 2. Go via tarball oficial (NO apt, evita version vieja) ---
if ! command -v go >/dev/null 2>&1; then
  echo "[*] instalando Go $GO_VERSION ($OS/$GOARCH) desde go.dev ..."
  TMP="$(mktemp -d)"
  curl -fsSL "https://go.dev/dl/go${GO_VERSION}.${OS}-${GOARCH}.tar.gz" -o "$TMP/go.tgz"
  if [ "$USE_SYSTEMD" = true ]; then
    rm -rf /usr/local/go && tar -C /usr/local -xzf "$TMP/go.tgz"
    export PATH="/usr/local/go/bin:$PATH"
  else
    tar -C "$TMP" -xzf "$TMP/go.tgz" && export PATH="$TMP/go/bin:$PATH"
  fi
  rm -rf "$TMP"
else
  echo "[*] Go presente: $(go version)"
fi

# --- 3. Clonar fuentes (idempotente) ---
mkdir -p "$BUILD_DIR"
clone() {
  local repo="$1" dir="$2" commit="$3"
  if [ -d "$dir/.git" ]; then echo "[*] $dir ya existe, fetch"; git -C "$dir" fetch --quiet; else git clone --quiet "$repo" "$dir"; fi
  if [ -n "${commit:-}" ]; then
    if [ "$commit" = "<PIN_COMMIT_PICOCLAW>" ]; then
      echo "[WARN] PIN_COMMIT_PICOCLAW NO FIJADO. PicoClaw es <v1.0: define la env PIN_COMMIT_PICOCLAW antes de producir."
    else
      git -C "$dir" checkout --quiet "$commit"
    fi
  fi
}
clone "$HARNESSLESS_REPO" "$BUILD_DIR/go-harnessless" ""
clone "$PICOCLAW_REPO"    "$BUILD_DIR/picoclaw"     "$PIN_COMMIT_PICOCLAW"

# --- 4. Parche go-harnessless (HARNESSLESS_CDP_URL -> wss remoto) ---
"$REPO_DIR/scripts/patch-harnessless.sh" "$BUILD_DIR/go-harnessless"

# --- 5. Build estatico (CGO_ENABLED=0) ---
echo "[*] build estatico go-harnessless ..."
( cd "$BUILD_DIR/go-harnessless" && CGO_ENABLED=0 go build -trimpath -ldflags '-s -w' -o "$INSTALL_BIN/go-harnessless" . )
echo "[*] build estatico picoclaw ..."
( cd "$BUILD_DIR/picoclaw" && CGO_ENABLED=0 go build -trimpath -ldflags '-s -w' -o "$INSTALL_BIN/picoclaw" . )

# --- 6. .env + unit systemd ---
if [ "$USE_SYSTEMD" = true ]; then
  mkdir -p /opt/agent-browser-use-cloud
  cp -r "$REPO_DIR/config" "$REPO_DIR/scripts" /opt/agent-browser-use-cloud/ 2>/dev/null || true
  [ -f /opt/agent-browser-use-cloud/.env ] || cp "$REPO_DIR/.env.example" /opt/agent-browser-use-cloud/.env
  cp "$REPO_DIR/systemd/agent-browser-use-cloud.service" /etc/systemd/system/
  systemctl daemon-reload
  echo "[*] unit instalada. Edita /opt/agent-browser-use-cloud/.env y: systemctl enable --now agent-browser-use-cloud"
else
  cp "$REPO_DIR/.env.example" "$REPO_DIR/.env" 2>/dev/null || true
  echo "[*] sin root: edita $REPO_DIR/.env y usa ./scripts/start.sh"
fi

echo "[ok] instalacion completada. Binarios en $INSTALL_BIN (picoclaw, go-harnessless)."
