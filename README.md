# dev-kit — plugin `dev` pre Claude Code

- Plugin `dev`: kontroly hneď po edite, Stop kontrola na konci ťahu, commit gate, príkazy `/dev:*` a šablóny projektov.
- Stack: PHP Nette a Symfony, Python (pytest, ruff, mypy). Všetko riadi projektový `.claude/devkit.json` (kontrakt: `docs/SPEC.md` §3).
- Bez `.claude/devkit.json` sú hooky no-op — úvodná karta len raz za deň poradí `/dev:project-init`.
- Časť obsahu je prevzatá z ECC (MIT) → `plugins/dev/PROVENANCE.md`, licencia `plugins/dev/LICENSES/ECC-MIT.txt`.
- Licencia kitu: MIT → `LICENSE`.

## Inštalácia

```bash
brew install jq                                   # bez jq hooky mlčia
claude plugin marketplace add xentrix161/claude-dev-kit
claude plugin install dev@dev-kit --scope user
```

- Aktualizácia na vydanú verziu: `claude plugin update dev@dev-kit`.
- Vývoj kitu: marketplace z lokálnej cesty (`claude plugin marketplace add <cesta-ku-klonu>`) → plugin sa načíta in-place: úprava kitu platí po `/reload-plugins` alebo v novej session, verzia sa nezvyšuje.
- Jednorazový test bez inštalácie: `claude --plugin-dir <cesta-ku-klonu>/plugins/dev`.
- Overenie: `claude plugin list` (`dev@dev-kit` enabled), `make details` (inventár + always-on tokeny).
- Pôvodný `~/.claude/skills/task-tldr` presuň mimo `~/.claude/skills/` (záloha, napr. `~/.claude/backups/<dátum>/`) — kit nesie jeho presnú kópiu a dva skilly s rovnakým menom by sa v zozname zdvojili. Staré `~/.claude/commands/{commit,review,test,explain,security}.md` nechaj 2 týždne popri kite, potom ich zmaž (dve verzie príkazu mätú model).

## Nastavenie projektu

- V projekte `/dev:project-init --dry-run` → plán súborov a návrh `.claude/devkit.json`; potom `/dev:project-init`.
- Nič neprepíše bez súhlasu; lokálne (`.git/info/exclude`) alebo pre tím (commit `.claude/` robíš ty).
- `.claude/worktrees/` ide do `.git/info/exclude` (lokálne) alebo `.gitignore` (tím).
- Prvý `/dev:check --full` = východiskový stav; staré zlyhania do `check.knownFailures` len so súhlasom, inak commit gate zablokuje každý commit.
- Aktualizácia skopírovaných šablón po release kitu: `/dev:project-init --sync`.

## Hooky — bežia samy

| Udalosť | Skript | Čo robí | Výsledok pri náleze |
|---|---|---|---|
| SessionStart (štart, resume, `/clear`, kompakcia) | `session-card.sh` | karta ≤ 10 riadkov: stack, kontajner, git, posledný handoff, zámok testu, pripomienka údržby | karta (kontext pre Clauda); varovania (jq, kontajner, údržba, worktree) zobrazí aj tebe |
| PreToolUse Edit/Write | `pre-edit.sh` | edit testu zamknutého počas `/dev:fix`; edit už commitnutej migrácie | deny / ask |
| PreToolUse Bash (`git commit`) | `pre-bash.sh` | tajomstvá a zakázané súbory v commite; commit gate = PASS z `/dev:check` pre presne tento obsah | deny |
| PostToolUse Edit/Write | `on-edit.sh` | lint podľa prípony + guardy (debug výpis, `die()`, `{!$var}`, `@`, SQL reťazcom) a tajomstvá len v pridaných riadkoch | exit 2 → Claude opraví hneď |
| Stop | `stop-check.sh` | `check.sh --stop` nad súbormi tejto session + párové pravidlá (`pairs`) a zmazané test metódy | blok ťahu; po 3× rovnakom stave len upozornenie; párové pravidlá a zmazané test metódy → pripomienka bez chyby |

- Nebežiaci kontajner, chýbajúci nástroj alebo `jq` → kontrola sa preskočí, nikdy neblokuje; commit gate však commit kódu bez PASS odmietne.
- Logy: `~/.claude/dev-kit/` (`decisions.jsonl`, `errors.log`, `projects/<hash>/logs/`); iné miesto cez `DEVKIT_DATA`.

## Príkazy

| Príkaz | Čo robí |
|---|---|
| `/dev:check [--quick · --full · --auto]` | jediný zdroj pravdy kontrol (`scripts/check.sh`); PASS odomkne commit gate |
| `/dev:commit` | `check --auto` → zoskupenie + správa `[#XX] typ: výstih` → jedno potvrdenie; nikdy push |
| `/dev:review [branch [base]] [--security]` | review diffu: Bugs · Security · súlad s `docs/plans/*.md` · zastarané CLAUDE.md/rules |
| `/dev:test` | RED → GREEN → REFACTOR s dôkazom (PHPUnit, pytest) |
| `/dev:debug` | logy a stav prostredia → hypotéza → minimálny repro → návrh opravy |
| `/dev:fix [--unlock]` | repro test → zámok testu → oprava kódu → `check --auto` → odomknutie |
| `/dev:plan` | `docs/plans/<úloha>-<slug>.md` pre úlohy nad 3 súbory alebo rizikové cesty |
| `/dev:learn` | návrhy do pamäte, `.claude/rules/` alebo `guards`/`pairs`; zapíše len schválené |
| `/dev:handoff` | stav práce do handoff dokumentu, potom `/clear` |
| `/dev:explain` | čo to robí · ako to funguje · závislosti · riziká pri zmene |
| `/dev:stats [--days N] [--all]` | rozhodnutia hookov v aktuálnom projekte (`--all` = všetky), najhlučnejšie pravidlá, PASS na prvý raz |
| `/dev:project-init [--dry-run · --sync]` | nastavenie projektu zo šablóny |
| `/dev:ecc-production-audit` | audit pred nasadením (len ručne) |

- Referenčné skilly (model ich načíta sám, keď sa hodia; väčšina len pri súboroch z `paths:`): `ecc-mysql-patterns`, `ecc-e2e-testing`, `ecc-change-impact`, `ecc-accessibility`, `ecc-python-patterns`, `ecc-python-testing`, `task-tldr`.
- Agenty (read-only): `dev:ecc-silent-failure-hunter`, `dev:ecc-pr-test-analyzer`, `dev:ecc-a11y-architect`, `dev:ecc-performance-optimizer`.
- Vrstva B (do projektu na požiadanie cez `project-init`): `ecc-design-system`, `ecc-api-design`, `ecc-inherit-legacy-style`, `ecc-seo`.

## Hlučný hook — nahlásiť a stlmiť

- Hooky sa nevypínajú, ladia sa: `/dev:stats` ukáže najhlučnejšie pravidlá.
- Nahlás: id pravidla z hlášky (`guard:sql-concat`, `lint:.php`, …) + `súbor:riadok` + prečo je to falošný poplach.
- Okamžitá úľava v jednom projekte: `"disabledRules": ["guard:sql-concat"]` v `.claude/devkit.json`.
- Id pre `disabledRules`: `guard:<id>` (napr. `guard:test-skip`), `lint:<ext>`, `step:<id>`, `pair:<id>`, `secrets`, `migrations`, `testLock`, `stopCheck`, `commitGate`, `testRemoved`.
- Trvalá oprava: vzor alebo prah v šablóne kitu + prípad v `tests/selftest.sh`, potom `/dev:project-init --sync`.

## Vypnutie kitu

- V session: `/plugin` → Installed → `dev` → Disable, potom `/reload-plugins`.
- Zo shellu: `claude plugin disable dev@dev-kit` (platí od novej session alebo `/reload-plugins`).
- Len jeden projekt: `"enabledPlugins": {"dev@dev-kit": false}` v `.claude/settings.local.json` projektu.
- Len časť: `"stopCheck": false` alebo `"commitGate": {"enabled": false}` v `.claude/devkit.json`.

## Údržba (P1–P5)

| Prúd | Ako | Kedy |
|---|---|---|
| P1 Vlastné zmeny | edit → `/reload-plugins`; pred commitom `make check` (validate --strict, selftest, always-on ≤ 3k tok.) | pri každej zmene |
| P2 Tím (od F5) | GitHub marketplace `xentrix161/claude-dev-kit`; kolegovia dostanú len vydané verzie (`autoUpdate` alebo `claude plugin update dev@dev-kit`) | pri release |
| P3 Upstream ECC | `make upstream` → zoznam zmenených prevzatých kusov; preberá sa ručne, potom posun pinu v `PROVENANCE.md` | mesačne; karta pripomenie po 30 dňoch |
| P4 Claude Code | po `claude update` `make check`; changelog → zabudovaná funkcia môže nahradiť kus kitu, ten sa zruší | mesačne |
| P5 Projekty | skopírované šablóny majú hlavičku: markdown `<!-- dev-kit: … -->`, `.worktreeinclude` `# dev-kit: …`, JSON bez hlavičky (porovnáva sa podľa id/kľúčov); `/dev:project-init --sync` | po release šablón |

- `make upstream` robí `git fetch` v `~/Projects/_tools/ECC` a zapíše `~/.claude/dev-kit/maintenance.json`; offline: `bash tools/upstream.sh --no-fetch` (dátum nezapíše).

## Vydanie

```bash
make release VERSION=0.2.0             # verzia v plugin.json, validate --strict, tag --dry-run
# doplň CHANGELOG.md: ## 0.2.0 — RRRR-MM-DD
git add plugins/dev/.claude-plugin/plugin.json CHANGELOG.md
git commit -m "vydanie dev 0.2.0"
claude plugin tag --push plugins/dev   # tag dev--v0.2.0, overí zhodu s marketplace
```

- Verzia je len v `plugins/dev/.claude-plugin/plugin.json`, marketplace záznam ju nemá.
- Bez zvýšenia verzie kolegovia novú verziu nedostanú; tvoja in-place inštalácia verziu ignoruje.

## Závislosti

- `bash` (stačí macOS 3.2), `git`, `jq` — bez `jq` hooky mlčia a karta to povie (`brew install jq`).
- `docker` len keď `devkit.json` má `container`.
- Claude Code 2.1.308+ (overené), `make` (GNU aj BSD), `perl` voliteľne (presné ms v logu).

## Vývoj kitu

- Kontrakty (názvy, cesty, výstupy): `docs/SPEC.md`.
- `make check` · `make selftest` · `make details` · `make upstream` · `make release VERSION=x.y.z` (`make help`).
- `make details` (`tools/details.sh`) stráži always-on ≤ 3 000 tok. bez príkazových skillov — `claude plugin details` ich počíta, hoci s `disable-model-invocation: true` ich popis v kontexte nie je.
- Skripty: `#!/usr/bin/env bash`, bash 3.2, bez GNU-only prepínačov; text pre ľudí po slovensky s plnou diakritikou; výstupy skillov stručne, ale úplne (záver prvý, celé vety, úplné zoznamy).
