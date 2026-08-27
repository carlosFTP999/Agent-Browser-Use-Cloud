#!/usr/bin/env bash
# scripts/patch-harnessless.sh — adaptacion remota de go-harnessless (ESPECIFICACIONES §2.1, ~10-20 LOC).
# Anade soporte a la env HARNESSLESS_CDP_URL: si esta presente, el daemon usa ese wss
# remoto via NewDaemon(wsURL) en lugar de GetChromeWSURL (Chrome LOCAL).
#
# Uso: patch-harnessless.sh <dir-fuente-go-harnessless>
set -euo pipefail

HL_DIR="${1:-${HARNESSLESS_DIR:-}}"
[ -n "$HL_DIR" ] || { echo "[fatal] uso: $0 <dir go-harnessless>"; exit 1; }
[ -d "$HL_DIR" ] || { echo "[fatal] no existe: $HL_DIR"; exit 1; }

# Localizar el archivo que define func RunDaemon (y usa GetChromeWSURL).
SRC="$(grep -rl "func RunDaemon" "$HL_DIR" --include='*.go' | head -n1)"
[ -n "$SRC" ] || { echo "[fatal] no se encontro func RunDaemon en $HL_DIR"; exit 1; }
echo "[*] parcheando $SRC"

# Idempotencia: no parchear dos veces.
if grep -q "HARNESSLESS_CDP_URL" "$SRC"; then
  echo "[*] ya parcheado (HARNESSLESS_CDP_URL presente). skip."
  exit 0
fi

# Asegurar import "os" en el archivo.
if ! grep -q '"os"' "$SRC"; then
  # insertar "os" junto a la primer import de paquete estandar.
  awk '!/__PATCHED_IMPORT__/ && /^import \(/ {print; print "\t\"os\""; next} {print}' "$SRC" > "$SRC.tmp" && mv "$SRC.tmp" "$SRC"
fi

# Inyectar el override justo despues de la apertura de func RunDaemon.
# NuevoDaemon(wsURL) ya existe en el repo (soporta cualquier ws/wss).
MARKER='// [patch] remote CDP adapter (HARNESSLESS_CDP_URL)'
INJECT=$(cat <<'GO'

	// [patch] remote CDP adapter (HARNESSLESS_CDP_URL)
	if remote := os.Getenv("HARNESSLESS_CDP_URL"); remote != "" {
		log.Printf("[harnessless] usando cdpUrl remoto desde HARNESSLESS_CDP_URL")
		return NewDaemon(remote)
	}
GO
)

awk -v marker="$MARKER" -v inject="$INJECT" '
  !done && /^func RunDaemon/ {print; getline; print; print inject; done=1; next}
  {print}
' "$SRC" > "$SRC.tmp" && mv "$SRC.tmp" "$SRC"

# Verificar que compila (solo chequeo de sintaxis si go disponible).
if command -v go >/dev/null 2>&1; then
  ( cd "$HL_DIR" && go build -o /dev/null . ) && echo "[ok] go-harnessless compila tras parche." \
    || { echo "[warn] build de go-harnessless fallo; revisa el parche manualmente."; }
fi
echo "[ok] parche aplicado: HARNESSLESS_CDP_URL -> NewDaemon(wss remoto)."
