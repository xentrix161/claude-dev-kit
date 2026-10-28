# dev-kit

Plugin `dev` pre Claude Code. Claude si po sebe skontroluje kód (lint, testy, statickú analýzu) skôr, ako povie „hotovo“ alebo commitne. Podporuje PHP Nette (Dibi alebo Doctrine), PHP Symfony a Python.

## Inštalácia

```bash
brew install jq                                   # bez jq hooky mlčia
claude plugin marketplace add xentrix161/claude-dev-kit
claude plugin install dev@dev-kit --scope user
```

Novú verziu stiahneš príkazom `claude plugin update dev@dev-kit`. Potrebuješ Claude Code 2.1.308+ a `jq`, `docker` len pre projekty s kontajnerom.

## Zapnutie v projekte

Projekt bez `.claude/devkit.json` kit nechá na pokoji: hooky v ňom nič nerobia. Nastavenie vytvoríš takto:

1. `/dev:project-init --dry-run` ukáže plán súborov a návrh `.claude/devkit.json`. Nič nezapíše.
2. `/dev:project-init` zapíše nastavenie, rules a `CLAUDE.md`. Existujúci súbor zmení len so súhlasom. Nastavenie môže ostať lokálne (`.git/info/exclude`) alebo ho commitneš pre tím.
3. `/dev:check --full` uloží východiskový stav. Staré zlyhania sa zapíšu do `check.knownFailures` len so súhlasom, inak by commit gate blokoval každý commit.

Po novej verzii kitu obnovíš skopírované šablóny príkazom `/dev:project-init --sync`.

## Čo robí sám

| Kedy | Čo sa stane |
|---|---|
| po každom edite | Lint a guardy na debug výpis, `die()`, `{!$var}`, `@` a SQL skladané reťazcom. Pridané riadky prehľadá aj na tajomstvá. Claude nález opraví hneď. |
| na konci ťahu | Testy a analýza nad súbormi, ktoré Claude v session zmenil. Kým padajú, Claude nemôže skončiť (po 3 rovnakých pokusoch už len upozorní). |
| pred commitom | Commit prejde len s PASS z `/dev:check` pre presne ten obsah. Tajomstvá a lokálne configy (`config.local.neon`, `.env`) neprejdú. |
| pred editom | Pred zmenou už commitnutej migrácie sa Claude spýta. Počas `/dev:fix` je test zamknutý, takže Claude opraví kód, nie test. |
| pri štarte session | Karta so stackom, stavom kontajnera, gitom a posledným handoffom. |

Nebežiaci kontajner ani chýbajúci nástroj nič nezablokujú, kontrola sa len preskočí. Commit kódu bez PASS však commit gate odmietne.

## Príkazy

| Príkaz | Na čo |
|---|---|
| `/dev:check [--quick · --full]` | kontroly projektu; PASS odomkne commit |
| `/dev:commit` | kontrola, zoskupenie zmien a správa `[#XX] typ: výstih`; nikdy nerobí push |
| `/dev:review [branch [base]] [--security]` | review diffu: bugy, bezpečnosť, súlad s plánom, zastarané `CLAUDE.md` |
| `/dev:fix` | repro test → zámok testu → oprava kódu → kontrola |
| `/dev:test` | test najprv: RED → GREEN → REFACTOR (PHPUnit, pytest) |
| `/dev:debug` | logy a stav prostredia → hypotéza → minimálny repro → návrh opravy |
| `/dev:plan` | plán do `docs/plans/` pre väčšie alebo rizikové úlohy |
| `/dev:handoff` | stav práce do handoff dokumentu pred `/clear` |
| `/dev:explain` | čo kód robí, z čoho závisí a čo hrozí pri zmene |
| `/dev:learn` | návrhy pravidiel do pamäte alebo `.claude/rules/`; zapíše len schválené |
| `/dev:stats` | čo hooky zachytili a ktoré pravidlá sú najhlučnejšie |
| `/dev:project-init` | nastavenie projektu zo šablóny |
| `/dev:ecc-production-audit` | audit pred nasadením (len ručne) |

Referenčné skilly (MySQL, E2E, prístupnosť, Python, dopad zmeny, TLDR do tasku) a read-only agenti (tiché zlyhania, pokrytie testami, výkon, prístupnosť) sa načítajú samy, keď sa hodia. Skilly na dizajn systém, API, SEO a štýl legacy kódu skopíruje `/dev:project-init` do projektu len na požiadanie.

## Keď hook otravuje

- `/dev:stats` ukáže najhlučnejšie pravidlá.
- Pravidlo v projekte vypneš cez `"disabledRules": ["guard:sql-concat"]` v `.claude/devkit.json`. Id je v hláške hooku (`guard:<id>`, `lint:<ext>`, `step:<id>`, `pair:<id>`, `secrets`, `migrations`, `testLock`, `stopCheck`, `commitGate`, `testRemoved`).
- Kontrolu na konci ťahu alebo commit gate vypneš cez `"stopCheck": false` alebo `"commitGate": {"enabled": false}`.
- Kit v jednom projekte vypneš cez `"enabledPlugins": {"dev@dev-kit": false}` v `.claude/settings.local.json`, všade príkazom `claude plugin disable dev@dev-kit`.
- Falošný poplach nahlás ako issue: id pravidla, `súbor:riadok` a prečo nejde o chybu.

Logy sú v `~/.claude/dev-kit/`, iné miesto nastavíš cez `DEVKIT_DATA`.

## Vývoj kitu

```bash
git clone https://github.com/xentrix161/claude-dev-kit.git
claude plugin marketplace add ./claude-dev-kit    # in-place: zmena platí po /reload-plugins
make check                                        # validate --strict, selftest, rozpočet tokenov
```

- Kontrakt (názvy, cesty, výstupy, `devkit.json`): `docs/SPEC.md`. Ďalšie ciele vypíše `make help`.
- Jednorazový test bez inštalácie: `claude --plugin-dir ./claude-dev-kit/plugins/dev`.
- Skripty sú pre bash 3.2 (macOS) bez GNU-only prepínačov. Text pre ľudí je po slovensky s plnou diakritikou.
- `make details` stráži, aby trvalý kontext kitu ostal pod 3 000 tokenov.

### Údržba

- **Hlučné pravidlo:** oprav vzor alebo prah v šablóne kitu, pridaj prípad do `tests/selftest.sh` a v projektoch spusti `/dev:project-init --sync`.
- **Claude Code:** po `claude update` spusti `make check`. Ak novú funkciu Claude Code zvládne sám, príslušný kus kitu zruš.
- **ECC:** raz mesačne `make upstream` (karta to pripomenie po 30 dňoch) vypíše zmenené prevzaté kusy. Zmeny preber ručne a posuň pin v `plugins/dev/PROVENANCE.md`. Klon ECC hľadá v `~/Projects/_tools/ECC`, iný nastavíš cez `ECC_DIR`.

### Vydanie

```bash
make release VERSION=0.2.0             # verzia v plugin.json, validate --strict, tag --dry-run
# doplň CHANGELOG.md: ## 0.2.0 — RRRR-MM-DD
git add plugins/dev/.claude-plugin/plugin.json CHANGELOG.md
git commit -m "vydanie dev 0.2.0"
git push
claude plugin tag --push plugins/dev   # tag dev--v0.2.0, overí zhodu s marketplace
```

Verzia je len v `plugins/dev/.claude-plugin/plugin.json`. Bez jej zvýšenia ostatní novú verziu nedostanú; inštalácia z lokálnej cesty verziu ignoruje.

## Licencia

MIT, pozri `LICENSE`. Časť obsahu je prevzatá z [ECC](https://github.com/affaan-m/ECC) pod MIT: zoznam je v `plugins/dev/PROVENANCE.md`, licencia v `plugins/dev/LICENSES/ECC-MIT.txt`.
