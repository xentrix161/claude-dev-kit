# dev-kit — údržba kitu. Kompatibilné s GNU make 3.81+ aj BSD make (bez GNU funkcií).
# Detail: README.md, sekcie Údržba a Vydanie.

CLAUDE ?= claude
PLUGIN = plugins/dev
MANIFEST = $(PLUGIN)/.claude-plugin/plugin.json
BUDGET ?= 3000
VERSION ?=

.PHONY: help check validate selftest details upstream release

help:
	@echo "make check                   validate --strict (plugin + marketplace) + selftest + details"
	@echo "make validate                len claude plugin validate --strict"
	@echo "make selftest                tests/selftest.sh (bez dockeru a siete)"
	@echo "make details                 inventár a always-on tokeny pracovnej kópie (limit $(BUDGET))"
	@echo "make upstream                zmeny prevzatých kusov ECC voči origin/main (P3)"
	@echo "make release VERSION=x.y.z   verzia v plugin.json + validate + tag dry-run"

check: validate selftest details
	@echo "[dev-kit] make check: PASS"

validate:
	$(CLAUDE) plugin validate --strict $(PLUGIN)
	$(CLAUDE) plugin validate --strict .

selftest:
	@if [ ! -f tests/selftest.sh ]; then echo "[dev-kit] chýba tests/selftest.sh"; exit 1; fi
	bash tests/selftest.sh

# Pracovná kópia cez --plugin-dir: funguje aj bez inštalácie a ukazuje práve upravený stav.
details:
	@CLAUDE="$(CLAUDE)" BUDGET="$(BUDGET)" bash tools/details.sh $(PLUGIN)

upstream:
	@bash tools/upstream.sh

release:
	@if [ -z "$(VERSION)" ]; then echo "použitie: make release VERSION=x.y.z"; exit 2; fi
	@if ! echo "$(VERSION)" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$$'; then echo "[dev-kit] VERSION musí byť x.y.z, nie $(VERSION)"; exit 2; fi
	@command -v jq >/dev/null 2>&1 || { echo "[dev-kit] chýba jq (brew install jq)"; exit 1; }
	@n=$$(jq -r .name $(MANIFEST)); if git rev-parse -q --verify "refs/tags/$$n--v$(VERSION)" >/dev/null; then echo "[dev-kit] tag $$n--v$(VERSION) už existuje → zvoľ vyššiu verziu"; exit 2; fi
	@jq --arg v "$(VERSION)" '.version = $$v' $(MANIFEST) > $(MANIFEST).tmp && mv $(MANIFEST).tmp $(MANIFEST)
	@echo "[dev-kit] $(MANIFEST): version = $(VERSION)"
	@grep -qF "## $(VERSION) " CHANGELOG.md || echo "[dev-kit] doplň do CHANGELOG.md sekciu: ## $(VERSION) — <dátum>"
	$(CLAUDE) plugin validate --strict $(PLUGIN)
	$(CLAUDE) plugin tag --dry-run --force $(PLUGIN)
	@echo "ďalej: commit plugin.json + CHANGELOG.md, potom $(CLAUDE) plugin tag --push $(PLUGIN)"
