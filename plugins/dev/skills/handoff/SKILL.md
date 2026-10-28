---
name: handoff
description: "Zapíše stav práce (hotové, rozpracované, ďalší krok, rozhodnutia, súbory, overenie) do handoffDoc z devkit.json alebo docs/handoff.md, zaznamená ho pre úvodnú kartu a navrhne /clear."
argument-hint: "[názov]"
disable-model-invocation: true
allowed-tools:
  - 'Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/session-card.sh" --record-handoff *)'
---

# Handoff

Odovzdávka stavu pred `/clear` alebo koncom dňa, aby ďalšia session nadviazala bez hľadania. Po slovensky, stručne, ale úplne.
Názov: `$ARGUMENTS` (prázdne → zvoľ výstižný, najviac 8 slov).

## 1. Zisti stav

- z konverzácie: čo je hotové, čo rozpracované, čo sa rozhodlo a prečo, čo ostalo otvorené
- git: `git branch --show-current`, `git status --short`, `git diff --stat HEAD`, `git log --oneline -5`
- paralelné sessions nad tým istým stromom: uveď len súbory, ktoré menila táto session; cudzie zmeny jednou odrážkou „mimo tejto session"
- overenie: posledný skutočný výsledok `/dev:check` alebo testov z tejto session (PASS/FAIL), nie odhad; nebežali → napíš „neoverené"

## 2. Kam

- `jq -r '.handoffDoc // empty' "${CLAUDE_PROJECT_DIR}/.claude/devkit.json"` (bez jq prečítaj súbor) → cesta relatívna ku koreňu projektu
- inak `docs/handoff.md` (neexistuje → vytvor s nadpisom `# Handoff`)
- dokument s vlastnými pravidlami (napr. „len otvorené body") → dodrž ich; čo tam nepatrí, vynechaj alebo len odkáž
- novú sekciu pridaj na koniec; staršie sekcie nemeň

## 3. Sekcia

```markdown
## Handoff YYYY-MM-DD HH:MM — <názov>

- **Vetva:** `<vetva>` · posledný commit `<sha> <správa>`
- **Hotové:** …
- **Rozpracované:** … (`súbor:riadok`, čo chýba)
- **Ďalší krok:** jedna konkrétna akcia
- **Rozhodnutia:** … (prečo, ak to nie je zrejmé)
- **Zmenené súbory:** `a.php`, `b.latte` (necommitnuté | v `<sha>`)
- **Overenie:** `/dev:check` → PASS/FAIL/neoverené · príkaz, ktorý stav potvrdí
- **Otvorené:** otázky na používateľa
```

- čas: `date '+%Y-%m-%d %H:%M'`
- odrážky krátke, prázdnu položku vynechaj
- bez tajomstiev, hesiel, osobných a produkčných dát

## 4. Zaznamenaj pre úvodnú kartu

Presne takto:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/session-card.sh" --record-handoff "<cesta>" "<názov>" --project "${CLAUDE_PROJECT_DIR}" < /dev/null
```
- `<cesta>` relatívne ku koreňu projektu, `<názov>` rovnaký ako v nadpise sekcie
- zlyhanie → jedna veta s chybou; dokument ostáva zapísaný

## 5. Výstup

- `Handoff zapísaný → <cesta>` (necommitnutý)
- ďalší krok jednou vetou a všetky otvorené body a otázky (každý jedným riadkom), nič nevynechaj
- trvalé poučenie zo session (korekcia, konvencia) → navrhni `/dev:learn`
- posledný riadok: `Teraz /clear — úvodná karta ukáže odkaz na handoff; v novej session napíš „pokračuj podľa <cesta>“.`
