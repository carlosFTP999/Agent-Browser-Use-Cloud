# Makefile — targets de despliegue (sin Python en prod).
# Binarios Go estaticos + curl/jq.

REPO_DIR := $(CURDIR)
SCRIPTS  := $(REPO_DIR)/scripts

.PHONY: install build smoke-test start stop clean

install:
	@bash $(SCRIPTS)/install.sh

build:
	@BUILD_DIR=$(REPO_DIR)/build bash -c '\
	  export PATH="/usr/local/go/bin:$$PATH"; \
	  # Commit fijado de PicoClaw (rama main). PicoClaw es <v1.0 (API inestable): \
	  # este hash es el pin por defecto, pero puede sobreescribirse con la env \
	  # PIN_COMMIT_PICOCLAW (p.ej. PIN_COMMIT_PICOCLAW=<otro-hash> make build). \
	  PIN_COMMIT_PICOCLAW="$${PIN_COMMIT_PICOCLAW:-bbf6893ca7afad27f1d00a0f5a45982a549c6ed6}"; \
	  git clone --quiet https://github.com/browser-use/go-harnessless $$BUILD_DIR/go-harnessless 2>/dev/null || true; \
	  if [ -d $$BUILD_DIR/picoclaw/.git ]; then git -C $$BUILD_DIR/picoclaw fetch --quiet; else git clone --quiet https://github.com/sipeed/picoclaw $$BUILD_DIR/picoclaw; fi; \
	  git -C $$BUILD_DIR/picoclaw checkout --quiet "$$PIN_COMMIT_PICOCLAW"; \
	  bash $(SCRIPTS)/patch-harnessless.sh $$BUILD_DIR/go-harnessless; \
	  (cd $$BUILD_DIR/go-harnessless && CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o bin/go-harnessless .); \
	  (cd $$BUILD_DIR/picoclaw && CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o bin/picoclaw .)'

smoke-test:
	@bash $(SCRIPTS)/smoke-test.sh

start:
	@bash $(SCRIPTS)/start.sh

stop:
	@bash $(SCRIPTS)/stop.sh

clean: stop
	@rm -rf $(REPO_DIR)/build $(REPO_DIR)/bin/*.sock $(REPO_DIR)/logs
	@echo "[ok] limpieza local (no toca /usr/local/bin ni systemd)."
