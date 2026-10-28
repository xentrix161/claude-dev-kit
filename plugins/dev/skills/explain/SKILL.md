---
name: explain
description: "Vysvetlí kód (súbor, triedu, metódu, riadky): Čo to robí, Ako to funguje, Závislosti, Riziká pri zmene. Hĺbka podľa požiadavky, so súbor:riadok odkazmi."
argument-hint: "<súbor | trieda | metóda | súbor:od-do> [--detail]"
disable-model-invocation: true
---

# Explain

Vysvetli kód zrozumiteľne a vecne. Po slovensky. Cieľ: `$ARGUMENTS`

## 1. Cieľ

- Argument = súbor, trieda, metóda alebo `súbor:od-do`. Bez argumentu sa opýtaj: „Ktorý kód chceš vysvetliť? (súbor, trieda, metóda alebo riadky)"
- Hĺbka: predvolene stručne. `--detail`, „podrobne", „krok po kroku" → hlbšie. Rýchla otázka „čo to robí?" → len sekcia Čo to robí.

## 2. Čítanie

- cieľový kód prečítaj celý
- kontext podľa potreby: rodičovské triedy, interface, traity, config (neon, `services.yaml`, routy), šablóny
- kto to volá: Grep na názov triedy, metódy, služby alebo routy; testy, ktoré to pokrývajú
- ak existuje `docs/CODEMAPS/`, začni tam
- framework: `.claude/devkit.json` → `stack`, inak `composer.json` / `pyproject.toml`
- široké trasovanie cez veľa súborov → zabudovaný agent Explore s presnou otázkou; jeho odpoveď over v kóde

## 3. Výstup

### Čo to robí
- krátky odsek (2–4 celé vety): účel a kde sa to v appke prejaví

### Ako to funguje
- kroky v poradí vykonávania so `súbor:riadok`; neočividné miesta podrobnejšie
- použité vzory (Repository, Factory, Observer, Nette signál, Symfony subscriber…) — jedna veta, čo znamenajú

### Závislosti
- od čoho to závisí: služby, tabuľky/entity, config
- čo závisí od toho: volajúci (`súbor:riadok`), routy, šablóny, CLI/cron

### Riziká pri zmene
- čo sa môže rozbiť a vedľajšie účinky (DB triggery, cache, odpovede API, JS naviazaný na markup)
- testy, ktoré spustiť (`/dev:check`, konkrétny test cez `--filter`)

## Pravidlá

- krátke odseky celých viet a odrážky podľa obsahu; `súbor:riadok` namiesto prerozprávania kódu; blok kódu len keď je nosný
- framework koncept vysvetli krátko (napr. „Symfony Event Subscriber — reaguje na udalosti v systéme")
- analógia len keď naozaj pomôže, jedna veta
- bug alebo podozrivé miesto spomeň jednou odrážkou `Pozor: súbor:riadok — výstih`, neopravuj
- čo si nevidel v kóde, označ „nepreverené" — nevymýšľaj
