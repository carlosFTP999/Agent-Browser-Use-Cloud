#!/usr/bin/env bash
# scripts/smoke-test.sh — §7a: valida POST /api/v4/browsers (fallback /api/v2/browsers),
# extrae cdpUrl, confirma 200; opcionalmente arranca go-harnessless y verifica el socket.
# Sin Python. Requiere curl + jq + (opcional) go-harnessless en PATH.
set -uo pipefail

ENV_FILE="${ENV_FILE:-.env}"
[ -f "$ENV_FILE" ] && set -a && . "$ENV_FILE" && set +a

KEY="${BROWSER_USE_API_KEY:-${X_BROWSER_USE_API_KEY:-}}"
PROFILE_ID="${PROFILE_ID:-prof_smoke01}"
PROXY="${PROXY_COUNTRY_CODE:-null}"
BASE="https://api.browser-use.com"

[ -n "$KEY" ] || { echo "[fatal] BROWSER_USE_API_KEY no definida (copia .env.example a .env)."; exit 1; }

BODY=$(jq -n --arg pid "$PROFILE_ID" --argjson proxy "$PROXY" \
  '{profileId:$pid, proxyCountryCode:$proxy, timeout:900}')

echo "[*] POST $BASE/api/v4/browsers ..."
OK_VER="v4"
RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE/api/v4/browsers" \
  -H "X-Browser-Use-API-Key: $KEY" -H "Content-Type: application/json" -d "$BODY")
CODE=$(echo "$RESP" | tail -n1); BODY_JSON=$(echo "$RESP" | sed '$d')

if [ "$CODE" = "404" ]; then
  echo "[*] v4 -> 404, fallback a /api/v2/browsers ..."
  OK_VER="v2"
  RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE/api/v2/browsers" \
    -H "X-Browser-Use-API-Key: $KEY" -H "Content-Type: application/json" -d "$BODY")
  CODE=$(echo "$RESP" | tail -n1); BODY_JSON=$(echo "$RESP" | sed '$d')
fi

echo "[*] HTTP $CODE"
echo "$BODY_JSON" | jq . 2>/dev/null || echo "$BODY_JSON"

if [ "$CODE" != "200" ]; then
  echo "[fatal] no se obtuvo 200 de la API BaaS. Revisa API key / version."
  exit 1
fi

BROWSER_ID=$(echo "$BODY_JSON" | jq -r '.id // empty')
CDP_URL=$(echo "$BODY_JSON" | jq -r '.cdpUrl // empty')
[ -n "$CDP_URL" ] || { echo "[fatal] respuesta 200 sin cdpUrl."; exit 1; }
echo "[ok] browserId=$BROWSER_ID cdpUrl=$CDP_URL"

# --- Paso opcional: arrancar go-harnessless y verificar socket ---
SOCK="${HARNESSLESS_SOCK:-/tmp/harnessless.sock}"
if command -v go-harnessless >/dev/null 2>&1; then
  echo "[*] arrancando go-harnessless con HARNESSLESS_CDP_URL ..."
  export HARNESSLESS_CDP_URL="$CDP_URL"
  rm -f "$SOCK"
  go-harnessless >/dev/null 2>&1 &
  HL_PID=$!
  for i in $(seq 1 20); do
    [ -S "$SOCK" ] && break
    sleep 0.5
  done
  if [ -S "$SOCK" ]; then
    echo "[ok] socket presente: $SOCK (puente CDP conectado al wss remoto)."
  else
    echo "[warn] socket $SOCK no aparecio tras 10s."
  fi
  kill "$HL_PID" 2>/dev/null || true
else
  echo "[warn] go-harnessless no en PATH; omitti verificacion de socket. (corre scripts/install.sh)"
fi

# Liberar la sesion de prueba (no quemar una de las 3 concurrentes).
if [ -n "$BROWSER_ID" ] && command -v curl >/dev/null 2>&1; then
  curl -s -X DELETE "$BASE/api/$OK_VER/browsers/$BROWSER_ID" -H "X-Browser-Use-API-Key: $KEY" >/dev/null
  echo "[ok] sesion de prueba liberada (DELETE $OK_VER)."
fi
echo "[done] smoke test OK."
