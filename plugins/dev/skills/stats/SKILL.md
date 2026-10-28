---
name: stats
description: "Štatistika rozhodnutí hookov dev-kitu za obdobie (bloky, zamietnutia, rýchlosť). Nájde hlučné pravidlá a navrhne úpravu .claude/devkit.json; bez súhlasu nič nemení."
argument-hint: "[--days N] [--all]"
disable-model-invocation: true
allowed-tools:
  - 'Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/stats.sh" *)'
---

# /dev:stats — ktoré hooky pomáhajú a ktoré otravujú

Hooky sa nevypínajú plošne, ladí sa jedno pravidlo. Komunikuj po slovensky.

## 1. Beh

- Argumenty: `$ARGUMENTS`; skriptu odovzdaj len `--days N` (predvolene 30) a `--all` (všetky projekty).
- Bez `--all`:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/stats.sh" --days <N> --project "${CLAUDE_PROJECT_DIR}"
```

- S `--all`: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/stats.sh" --days <N> --all` (bez `--project`).
- Žiadne rozhodnutia → `zatiaľ žiadne rozhodnutia hookov` a koniec. Projekt bez `.claude/devkit.json` → hooky tu nebežia, odporuč `/dev:project-init`.

## 2. Detail pravidla

- Log: `${DEVKIT_DATA:-$HOME/.claude/dev-kit}/decisions.jsonl`, riadok = JSON s `ts, project, session, hook, rule, decision, file, ms`.
- Kde sa pravidlo ozýva:

```bash
jq -c 'select(.rule == "<pravidlo>") | [.ts, .decision, .file]' "${DEVKIT_DATA:-$HOME/.claude/dev-kit}/decisions.jsonl" | tail -20
```

- Log je spoločný pre všetky projekty; bez `--all` filtruj aj podľa `.project`.
- Podozrenie na falošný poplach → v 2–3 takých súboroch nájdi miesto vzorom pravidla z `.claude/devkit.json` (`grep -nE`) a over, či išlo o skutočný problém.
- Id pravidiel: `guard:<id>`, `lint:<ext>`, `step:<id>`, `pair:<id>`, `secrets`, `migrations`, `testLock`, `testRemoved`, `stopCheck`, `commitGate`.

## 3. Vyhodnotenie

- **Hlučné pravidlo**: veľa `block`/`deny` v tých istých súboroch alebo na legacy kóde → presnejší `pattern`, výnimka (`secrets.allow`, `unless`), až nakoniec `disabledRules`.
- **Stop kontrola**: vysoký podiel blokov → ktorý krok padá; pomalý alebo nestabilný krok presuň do `modes: ["quick", "full"]`, opakovane známe zlyhanie do `knownFailures` (so súhlasom).
- **Commit gate**: zamietnutie, po ktorom prišiel PASS, je v poriadku; opakované zamietnutia = commity mimo `/dev:commit`.
- **Rýchlosť**: `on-edit` v priemere nad 2 s alebo `stop-check` nad 30 s → drahý lint či krok; navrhni `changedLinesOnly`, `runFiles` namiesto `run` alebo presun do `full`.
- `pass` je žiadaný stav, nie šum.

## 4. Návrhy

- Každý návrh: pravidlo → dôkaz (počet, príklad súboru) → konkrétna zmena `.claude/devkit.json` ako JSON úryvok → čo prestane chytať.
- Bez výslovného súhlasu nič nemeň. Po súhlase uprav len schválené položky a ukáž diff.
- Chyba vo vzore, ktorý dodáva samotný kit (nie projekt) → navrhni úpravu kitu, nie projektu.

## 5. Výstup

- Prvý riadok: obdobie, počet rozhodnutí, verdikt (napr. `30 dní · 412 rozhodnutí · 2 hlučné pravidlá`).
- Hlučné pravidlá: `N. pravidlo — N× block/deny — šum|oprávnené — návrh`.
- Rýchlosť: len hooky nad rozpočtom.
- Všetky hlučné pravidlá, každé jedným riadkom; na konci jedna otázka: ktoré návrhy použiť.
