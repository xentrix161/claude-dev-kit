# dev-kit — údržba kitu. Kompatibilné s GNU make 3.81+ aj BSD make (bez GNU funkcií).
# Detail: README.md, sekcie Údržba a Vydanie.

CLAUDE ?= claude
PLUGIN = plugins/dev
MANIFEST = $(PLUGIN)/.claude-plugin/plugin.json
BUDGET ?= 3000
VERSION ?=
EVAL_ARGS ?=

.PHONY: help check validate guards selftest details upstream release tag eval

help:
	@echo "make check                   validate --strict (plugin + marketplace) + guards + selftest + details"
	@echo "make validate                len claude plugin validate --strict"
	@echo "make guards                  celý strom skriptov: bash -n, guardy bash4 a gnu-only, shellcheck (ak je)"
	@echo "make selftest                tests/selftest.sh (bez dockeru a siete)"
	@echo "make details                 inventár a always-on tokeny pracovnej kópie (limit $(BUDGET))"
	@echo "make upstream                zmeny prevzatých kusov ECC voči origin/main (P3)"
	@echo "make eval [EVAL_ARGS=…]      eval suite príkazov /dev:* (claude plugin eval na sonnet, EVAL_MODEL/EVAL_JUDGE; stojí tokeny, nie je v make check)"
	@echo "make release VERSION=x.y.z   čistý main, verzia > posledný tag, sekcia v CHANGELOG, make check → verzia, dátum, validate, tag dry-run"
	@echo "make tag                     po zelenom CI na origin/main: claude plugin tag --push"

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

# Poistky pred zmenou plugin.json: čistý strom na main, verzia nad posledným tagom, sekcia v CHANGELOG, make check.
# Verzie porovnáva sort -t. -k…n (sort -V je GNU-only). Zlyhaný validate či tag --dry-run súbory vráti.
release:
	@if [ -z "$(VERSION)" ]; then echo "použitie: make release VERSION=x.y.z"; exit 2; fi
	@if ! echo "$(VERSION)" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$$'; then echo "[dev-kit] VERSION musí byť x.y.z, nie $(VERSION)"; exit 2; fi
	@command -v jq >/dev/null 2>&1 || { echo "[dev-kit] chýba jq (brew install jq)"; exit 1; }
	@if [ -n "$$(git status --porcelain)" ]; then echo "[dev-kit] strom nie je čistý (git status) — vydanie ide len z commitnutého stavu"; exit 2; fi
	@b=$$(git rev-parse --abbrev-ref HEAD); if [ "$$b" != main ]; then echo "[dev-kit] vydanie len z vetvy main, nie $$b"; exit 2; fi
	@n=$$(jq -r .name $(MANIFEST)); \
	if git rev-parse -q --verify "refs/tags/$$n--v$(VERSION)" >/dev/null; then echo "[dev-kit] tag $$n--v$(VERSION) už existuje → zvoľ vyššiu verziu"; exit 2; fi; \
	last=$$(git tag -l "$$n--v*" | sed "s/^$$n--v//" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$$' | sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1); \
	top=$$(printf '%s\n%s\n' "$$last" "$(VERSION)" | sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1); \
	if [ -n "$$last" ] && [ "$$top" != "$(VERSION)" ]; then echo "[dev-kit] verzia $(VERSION) nie je vyššia ako posledný tag $$n--v$$last"; exit 2; fi
	@awk -v h="## $(VERSION) " 'index($$0, h) == 1 { f = 1 } END { exit !f }' CHANGELOG.md || \
	{ echo "[dev-kit] CHANGELOG.md nemá sekciu ## $(VERSION) — nevydané → doplň ju, commitni a zopakuj make release"; exit 2; }
	$(MAKE) check
	@jq --arg v "$(VERSION)" '.version = $$v' $(MANIFEST) > $(MANIFEST).tmp && mv $(MANIFEST).tmp $(MANIFEST)
	@echo "[dev-kit] $(MANIFEST): version = $(VERSION)"
	@$(CLAUDE) plugin validate --strict $(PLUGIN) || { git checkout -- $(MANIFEST); echo "[dev-kit] validate zlyhal → $(MANIFEST) vrátený"; exit 1; }
	@d=$$(date +%Y-%m-%d); \
	awk -v h="## $(VERSION) — nevydané" -v r="## $(VERSION) — $$d" '$$0 == h { $$0 = r } { print }' CHANGELOG.md > CHANGELOG.md.tmp && mv CHANGELOG.md.tmp CHANGELOG.md; \
	echo "[dev-kit] CHANGELOG.md: $$(awk -v h="## $(VERSION) " 'index($$0, h) == 1 { print; exit }' CHANGELOG.md)"
	@$(CLAUDE) plugin tag --dry-run --force $(PLUGIN) || { git checkout -- $(MANIFEST) CHANGELOG.md; echo "[dev-kit] tag --dry-run zlyhal → $(MANIFEST) a CHANGELOG.md vrátené"; exit 1; }
	@echo "ďalej: git add $(MANIFEST) CHANGELOG.md, git commit -m \"vydanie dev $(VERSION)\", git push, po zelenom CI make tag"

# Tag až po zelenom CI presne na pushnutom HEAD; bez gh sa CI overiť nedá.
tag:
	@command -v jq >/dev/null 2>&1 || { echo "[dev-kit] chýba jq (brew install jq)"; exit 1; }
	@if [ -n "$$(git status --porcelain)" ]; then echo "[dev-kit] strom nie je čistý (git status) — taguje sa len commitnuté a pushnuté vydanie"; exit 2; fi
	@git fetch -q origin || { echo "[dev-kit] git fetch origin zlyhal — bez neho sa nedá overiť, že HEAD je pushnutý"; exit 2; }
	@h=$$(git rev-parse HEAD); o=$$(git rev-parse -q --verify origin/main); \
	if [ "$$h" != "$$o" ]; then echo "[dev-kit] HEAD nie je origin/main — najprv git push na main, potom make tag"; exit 2; fi
	@command -v gh >/dev/null 2>&1 || { echo "[dev-kit] chýba gh → nainštaluj gh alebo taguj ručne: claude plugin tag --push plugins/dev"; exit 2; }
	@r=$$(gh run list --commit "$$(git rev-parse HEAD)" --json conclusion,status -q '.[0] | "\(.status) \(.conclusion)"') || \
	{ echo "[dev-kit] gh run list zlyhal (gh auth status)"; exit 2; }; \
	case "$$r" in \
	  "completed success") echo "[dev-kit] CI pre $$(git rev-parse --short HEAD): success" ;; \
	  ""|"null null") echo "[dev-kit] CI pre HEAD ešte nebežalo — zopakuj make tag, keď beh po pushi skončí"; exit 2 ;; \
	  completed*) echo "[dev-kit] CI pre HEAD zlyhalo ($$r) — oprav, pushni a zopakuj make tag"; exit 2 ;; \
	  *) echo "[dev-kit] CI pre HEAD ešte beží ($${r% }) — zopakuj make tag po jeho skončení"; exit 2 ;; \
	esac
	$(CLAUDE) plugin tag --push $(PLUGIN)
