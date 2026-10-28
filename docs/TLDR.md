# dev kit — TLDR

Plugin `dev` pre Claude Code. Claude si po sebe skontroluje kód (lint, testy, statickú analýzu) skôr, ako povie „hotovo“ alebo commitne. Podporuje PHP Nette, PHP Symfony a Python.

## Čo robí sám, bez príkazu

- **Po každom edite** spustí lint a guardy na debug výpis, `die()`, `{!$var}`, `@` a SQL skladané reťazcom. Pridané riadky prehľadá aj na tajomstvá. Claude nález opraví hneď.
- **Na konci ťahu** pustí testy a analýzu nad súbormi, ktoré Claude v session zmenil. Keď padajú, Claude nemôže skončiť (po 3 rovnakých pokusoch už len upozorní).
- **Pred commitom** pustí commit len s PASS z `/dev:check` pre presne ten obsah. Tajomstvá a lokálne configy (`config.local.neon`, `.env`) do commitu neprejdú.
- **Ďalšie poistky:** pred editom už commitnutej migrácie sa Claude spýta. Počas `/dev:fix` je test zamknutý, takže Claude opraví kód, nie test.
- **Pri štarte session** ukáže kartu so stackom, stavom kontajnera, gitom a posledným handoffom.

Projekt bez `.claude/devkit.json` kit nechá na pokoji: hooky v ňom nič nerobia. Nebežiaci kontajner ani chýbajúci nástroj nikdy nič nezablokujú, kontrola sa len preskočí. Commit kódu bez PASS však commit gate odmietne.

## Inštalácia

```bash
brew install jq                                   # bez jq hooky mlčia
claude plugin marketplace add xentrix161/claude-dev-kit
claude plugin install dev@dev-kit --scope user
```

V projekte potom:

1. `/dev:project-init --dry-run` ukáže plán súborov a návrh `.claude/devkit.json`. Nič nezapíše.
2. `/dev:project-init` zapíše nastavenie, rules a `CLAUDE.md`. Existujúci súbor zmení len so súhlasom. Nastavenie môže ostať lokálne (`.git/info/exclude`) alebo ísť na commit pre tím.
3. `/dev:check --full` uloží východiskový stav. Staré zlyhania sa zapíšu do `knownFailures` len so súhlasom.

## Príkazy na každý deň

| Príkaz | Na čo |
|---|---|
| `/dev:check [--full]` | kontroly projektu; PASS odomkne commit |
| `/dev:commit` | kontrola, zoskupenie zmien a správa `[#XX] typ: výstih`; nikdy nerobí push |
| `/dev:review [branch]` | review diffu: bugy, bezpečnosť, súlad s plánom, zastarané `CLAUDE.md` |
| `/dev:fix` | repro test → zámok testu → oprava kódu → kontrola |
| `/dev:plan` | plán do `docs/plans/` pre väčšie alebo rizikové úlohy |
| `/dev:handoff` | stav práce do handoff dokumentu pred `/clear` |

Ďalšie príkazy: `/dev:test`, `/dev:debug`, `/dev:explain`, `/dev:learn`, `/dev:stats`. Referenčné skilly (MySQL, E2E, prístupnosť, Python) a read-only agenti sa načítajú samy, keď sa hodia.

## Keď hook otravuje

- `/dev:stats` ukáže najhlučnejšie pravidlá.
- Nahlás mi id z hlášky (napr. `guard:sql-concat`) spolu so `súbor:riadok` a dôvodom, prečo ide o falošný poplach.
- Pravidlo vypneš hneď cez `"disabledRules": ["guard:sql-concat"]` v `.claude/devkit.json`.
- Celý kit vypneš príkazom `claude plugin disable dev@dev-kit`.

## Stav

- Verzia 0.1.1, odskúšaná na prvých troch projektoch.
- Dostávaš len vydané verzie a aktualizuješ príkazom `claude plugin update dev@dev-kit`.
- Požiadavky: Claude Code 2.1.308+, `jq` a `docker` len pre projekty s kontajnerom.
- Detaily sú v `README.md`, kontrakt v `docs/SPEC.md`.
