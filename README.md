# Agent-Browser-Use-Cloud

Agente de automatización web 24/7 a **$0/mes**, desplegado como binario Go estático en un VPS free tier. Orquesta un navegador remoto (Browser-Use Cloud BaaS) y un LLM por API, **sin Python, sin Playwright, sin Chromium local**.

> Stack congelado (ver `RESTRICCIONES.md` / `ESPECIFICACIONES.md` del proyecto hermano `Browser-Use`):
> **PicoClaw (Go)** = Agent Runtime · **go-harnessless (Go)** = puente CDP `wss` remoto · **Browser-Use Cloud BaaS** = navegador `cdpUrl` · **LLM pluggable: cualquier proveedor compatible con la API de OpenAI** (OpenAI, Gemini, Groq, Together, etc.).

---

## Principios innegociables (de este repo)

- **$0/mes asumido.** No se documentan tarifas. `proxyCountryCode: null` (proxyless) salvo geo-targeting.
- **Sin Python en producción.** Solo binario Go estático + `curl` + `jq` + `go-harnessless`.
- **Reciclado obligatorio cada 15 min.** La sesión Free expira a los 15 min; se recicla reusando `profileId` (no se pierde estado).
- **LLM pluggable (proveedor-agnóstico).** Cliente OpenAI-compatible: se inyecta `LLM_BASE_URL` + `LLM_API_KEY` + `LLM_MODEL` por `.env`; no está hardcodeado a ningún proveedor.

---

## Arquitectura (resumen)

```
 PicoClaw (VPS, binario Go estático)
    ├─ arranca go-harnessless → /tmp/harnessless.sock
    ├─ REST BaaS: POST/DELETE /api/vX/browsers
    │        HARNESSLESS_CDP_URL=wss://… ──wss──▶ Browser-Use Cloud (navegador remoto)
    └── REST ──▶ LLM por API (compatible OpenAI: OpenAI, Gemini, Groq, Together, etc.)
```

---

## Prerequisites (VPS fresh — ej. GCP e2-micro, Debian/Ubuntu)

- VPS free tier (≈1 GB RAM). No requiere GPU ni Chromium local.
- `curl` y `jq` instalados (el script `install.sh` los verifica).
- Acceso a `https://api.browser-use.com` y al endpoint del LLM elegido.
- API key de Browser-Use Cloud (`https://cloud.browser-use.com`).
- (Opcional) root para instalar binarios en `/usr/local/bin` y la unit systemd. Sin root, los binarios quedan en `bin/` local.

---

## Pasos de instalación

1. **Clonar el repo**
   ```bash
   git clone <este-repo> agent-browser-use-cloud
   cd agent-browser-use-cloud
   ```

2. **Instalar dependencias y construir binarios**
   ```bash
   sudo ./scripts/install.sh
   ```
   `install.sh` es idempotente: instala Go (tarball oficial, no `apt`), clona PicoClaw (commit **fijado** `bbf6893ca7afad27f1d00a0f5a45982a549c6ed6` en `main`, es `<v1.0`; sobreescribible con la env `PIN_COMMIT_PICOCLAW`) y go-harnessless, aplica `scripts/patch-harnessless.sh` (adaptación `HARNESSLESS_CDP_URL`), hace build estático (`CGO_ENABLED=0`), instala `picoclaw`/`go-harnessless` a `/usr/local/bin` (o `bin/` local sin root) y recarga systemd. **No instala Python ni nada de pip.**

3. **Configurar entorno**
   ```bash
   cp .env.example .env
   nano .env   # rellenar BROWSER_USE_API_KEY, PROFILE_ID, LLM_*
   ```
   Ver `.env.example` para el significado de cada variable.

4. **Habilitar y arrancar el servicio**
   ```bash
   sudo systemctl enable --now agent-browser-use-cloud
   sudo systemctl status agent-browser-use-cloud
   ```
   La unit usa `EnvironmentFile=/opt/agent-browser-use-cloud/.env` (copiado por `install.sh`).

5. **Smoke test**
   ```bash
   ./scripts/smoke-test.sh
   ```
   Valida `POST /api/v4/browsers` (fallback `/api/v2/browsers`), extrae `cdpUrl`, confirma 200, y opcionalmente arranca go-harnessless para verificar que aparece `/tmp/harnessless.sock`.

### Reciclado 15 min (documentado)

El agente corre 24/7 pero la sesión Free vive ≤15 min. Un watchdog interno (ver `config/agent.example.yaml`) anticipa el reciclado: `DELETE` + `POST` reusando el mismo `profileId` → nuevo `cdpUrl` → re-set `HARNESSLESS_CDP_URL` → reconectar el puente. El estado del perfil (cookies, storage, logins) sobrevive.

### LLM pluggable (compatible con la API de OpenAI)

PicoClaw usa `openai-go`, así que el cliente *decide* es **proveedor-agnóstico**: apuntas a cualquier endpoint que hable la API de OpenAI. No se envía tráfico de decisión hasta fijar las tres variables en `.env`:

```bash
LLM_BASE_URL=        # vacío = OpenAI por defecto. ej. Gemini https://generativelanguage.googleapis.com/v1beta/openai/ | Groq https://api.groq.com/openai/v1 | Together https://api.together.xyz/v1
LLM_API_KEY=         # requerido
LLM_MODEL=           # ej. gemini-3-flash
LLM_MAX_IMAGES=5     # máximo imágenes por request multimodal (0 = sin imagen)
```

Recomendado: **free tier + multimodal** (texto+imagen, el flujo depende de entrada visual). Nunca modelo Pro/de pago. No enviar secretos ni PII en prompts. Candidatos válidos (libres y multimodal): Gemini `gemini-3-flash`, Groq vision, Together, u OpenAI según tu preferencia — **ninguno hardcodeado**. El `config/agent.example.yaml` expone lo mismo bajo `llm:`.

### Notas de $0

Tras navegación real, revisar billing en `cloud.browser-use.com` y vigilar créditos/minutos. `proxyCountryCode: null` mantiene egress $0.

---

## Estructura

```
.
├── README.md
├── .gitignore
├── .env.example
├── Makefile
├── config/agent.example.yaml
├── systemd/agent-browser-use-cloud.service
└── scripts/
    ├── install.sh
    ├── patch-harnessless.sh
    ├── smoke-test.sh
    ├── start.sh
    └── stop.sh
```

## Makefile targets

`make install` · `make build` · `make smoke-test` · `make start` · `make stop` · `make clean`
