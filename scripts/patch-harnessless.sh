#!/usr/bin/env bash
# scripts/patch-harnessless.sh — adaptacion remota de go-harnessless (ESPECIFICACIONES §2.1).
# Anade soporte a la env HARNESSLESS_CDP_URL: si esta presente, RunDaemon usa ese
# wss/ws remoto via NewDaemon(wsURL) en lugar de GetChromeWSURL (Chrome LOCAL).
#
# El parche es un unified diff EXACTO contra daemon.go: se genera en runtime localizando
# el bloque literal (func RunDaemon / GetChromeWSURL) y aplicandolo con `patch`. NO usa
# awk que adivina la firma. Es idempotente y reporta exito/error claramente.
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

# --- Localizar el bloque exacto a reemplazar (10 lineas: GetChromeWSURL .. cierre de NewDaemon) ---
START="$(grep -n "^	wsURL, err := GetChromeWSURL()" "$SRC" | head -n1 | cut -d: -f1)"
[ -n "$START" ] || { echo "[fatal] no se encontro 'wsURL, err := GetChromeWSURL()' en $SRC"; exit 1; }
END=$((START + 9))   # el bloque es exactamente 10 lineas (verificado en daemon.go de go-harnessless)

# --- Nuevo bloque (reemplazo exacto) ---
NEW_FILE="$(mktemp)"
cat > "$NEW_FILE" <<'NEW'
	// HARNESSLESS_CDP_URL overrides local Chrome discovery with a remote CDP
	// WebSocket endpoint (e.g. a wss:// tunnel provided by PicoClaw).
	var d *Daemon
	var err error
	if wsURL := os.Getenv("HARNESSLESS_CDP_URL"); wsURL != "" {
		log.Printf("using remote CDP endpoint from HARNESSLESS_CDP_URL")
		d, err = NewDaemon(wsURL)
		if err != nil {
			return fmt.Errorf("init daemon (remote CDP): %w", err)
		}
	} else {
		wsURL, err := GetChromeWSURL()
		if err != nil {
			return fmt.Errorf("locate Chrome: %w", err)
		}
		log.Printf("connecting to Chrome at %s", wsURL)

		d, err = NewDaemon(wsURL)
		if err != nil {
			return fmt.Errorf("init daemon: %w", err)
		}
	}
NEW

# --- Generar el unified diff a partir de una copia modificada (lineas correctas garantizadas) ---
MOD="$(mktemp)"
head -n "$((START - 1))" "$SRC" > "$MOD"
cat "$NEW_FILE" >> "$MOD"
tail -n +"$((END + 1))" "$SRC" >> "$MOD"

PATCH="$(mktemp)"
# diff con etiquetas relativos (a/daemon.go, b/daemon.go) para aplicar con patch -p1.
diff -u "$SRC" "$MOD" | sed -e "1s|^--- .*|--- a/daemon.go|" -e "2s|^+++ .*|+++ b/daemon.go|" > "$PATCH" || true
rm -f "$MOD" "$NEW_FILE"

if [ ! -s "$PATCH" ]; then
  echo "[fatal] el diff generado esta vacio; el bloque objetivo no coincide."
  rm -f "$PATCH"
  exit 1
fi

# --- Aplicar el parche ---
if patch -p1 --no-backup-if-mismatch -d "$HL_DIR" < "$PATCH"; then
  echo "[ok] parche aplicado: HARNESSLESS_CDP_URL -> NewDaemon(wss/ws remoto)."
else
  echo "[fatal] fallo al aplicar el parche. El archivo objetivo no coincide con el diff esperado."
  rm -f "$PATCH"
  exit 1
fi
rm -f "$PATCH"

# Verificar que compila (solo si go disponible).
if command -v go >/dev/null 2>&1; then
  ( cd "$HL_DIR" && go build -o /dev/null . ) && echo "[ok] go-harnessless compila tras parche." \
    || { echo "[fatal] build de go-harnessless fallo tras el parche; revisa el diff."; exit 1; }
else
  echo "[warn] go no disponible en este entorno; no se verifico la compilacion."
fi
