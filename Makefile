# dev-kit — údržba kitu. Kompatibilné s GNU make 3.81+ aj BSD make (bez GNU funkcií).
# Detail: README.md, sekcie Údržba a Vydanie.

CLAUDE ?= claude
PLUGIN = plugins/dev
MANIFEST = $(PLUGIN)/.claude-plugin/plugin.json
BUDGET ?= 3000
VERSION ?=
EVAL_ARGS ?=

.PHONY: help check validate guards selftest details upstream release eval

help:
	@echo "make check                   validate --strict (plugin + marketplace) + guards + selftest + details"
	@echo "make validate                len claude plugin validate --strict"
	@echo "make guards                  celý strom skriptov: bash -n, guardy bash4 a gnu-only, shellcheck (ak je)"
	@echo "make selftest                tests/selftest.sh (bez dockeru a siete)"
	@echo "make details                 inventár a always-on tokeny pracovnej kópie (limit $(BUDGET))"
	@echo "make upstream                zmeny prevzatých kusov ECC voči origin/main (P3)"
	@echo "make eval [EVAL_ARGS=…]      eval suite príkazov /dev:* (claude plugin eval na sonnet, EVAL_MODEL/EVAL_JUDGE; stojí tokeny, nie je v make check)"
	@echo "make release VERSION=x.y.z   verzia v plugin.json + validate + tag dry-run"

check: validate guards selftest details
	@echo "[dev-kit] make check: PASS"

validate:
	$(CLAUDE) plugin validate --strict $(PLUGIN)
	$(CLAUDE) plugin validate --strict .

# Hooky strážia guardmi len pridané riadky, tu celý strom. Vzory bash4 a gnu-only sú v .claude/devkit.json.
# shellcheck: SC1087 (regex "$VAR[…]"), SC1111 (slovenské úvodzovky), SC2034 (DK_* zdieľané cez lib.sh) sú falošné nálezy.
SH_DIRS = plugins/dev/scripts tests tools
SHELLCHECK_EXCLUDE = SC1087,SC1111,SC2034
guards:
	@command -v jq >/dev/null 2>&1 || { echo "[dev-kit] chýba jq"; exit 1; }
	@r=0; files=$$(find $(SH_DIRS) -name '*.sh' -type f | LC_ALL=C sort); tab=$$(printf '\t'); \
	for f in $$files; do bash -n "$$f" || r=1; done; \
	pats=$$(jq -r '.guards[] | select(.id == "bash4" or .id == "gnu-only") | "\(.id)\t\(.pattern)"' .claude/devkit.json) || exit 1; \
	[ "$$(printf '%s\n' "$$pats" | grep -c .)" = 2 ] || { echo "[dev-kit] .claude/devkit.json: chýba guard bash4 alebo gnu-only"; exit 1; }; \
	out=$$(printf '%s\n' "$$pats" | while IFS=$$tab read -r id pat; do \
	  h=$$(grep -nIE -e "$$pat" $$files); rc=$$?; \
	  [ $$rc -le 1 ] || echo "guard:$$id: neplatný vzor (grep -E exit $$rc)"; \
	  [ -z "$$h" ] || printf '%s\n' "$$h" | sed "s|^|guard:$$id: |"; \
	done); \
	[ -z "$$out" ] || { printf '%s\n' "$$out"; r=1; }; \
	if command -v shellcheck >/dev/null 2>&1; then shellcheck -S warning -e $(SHELLCHECK_EXCLUDE) $$files || r=1; \
	else echo "shellcheck: skip (nie je v PATH)"; fi; \
	n=$$(printf '%s\n' $$files | grep -c .); \
	if [ $$r = 0 ]; then echo "[dev-kit] guards: PASS · $$n skriptov"; else echo "[dev-kit] guards: FAIL"; exit 1; fi

selftest:
	@if [ ! -f tests/selftest.sh ]; then echo "[dev-kit] chýba tests/selftest.sh"; exit 1; fi
	bash tests/selftest.sh

# Pracovná kópia cez --plugin-dir: funguje aj bez inštalácie a ukazuje práve upravený stav.
details:
	@CLAUDE="$(CLAUDE)" BUDGET="$(BUDGET)" bash tools/details.sh $(PLUGIN)

# Eval suite plugins/dev/evals: model aj sudca stoja tokeny, preto nie je v check (README, Údržba).
# Sonnet pre agentov aj sudcu: predvolený model účtu býva drahší a sudca haiku dáva falošné FAIL.
EVAL_MODEL ?= sonnet
EVAL_JUDGE ?= sonnet
eval:
	$(CLAUDE) plugin eval $(PLUGIN) --ablation with-without --scaffold --allow-tools Bash Edit Write --model $(EVAL_MODEL) --judge-model $(EVAL_JUDGE) $(EVAL_ARGS)

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
