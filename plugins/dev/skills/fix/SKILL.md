---
name: fix
description: "Oprava bugu s dôkazom: fakty, červený regresný test, zámok testu, oprava kódu bez zásahu do testu, check.sh --auto. Argument --unlock len odomkne zamknutý test."
argument-hint: "<čo je pokazené> | --unlock"
disable-model-invocation: true
allowed-tools:
  - 'Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/check.sh" *)'
  - 'Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-lock.sh" *)'
---
<!-- postup z ECC commands/orch-fix-defect.md @ b92f181, prestavané (zámok testu, check.sh) -->

# /dev:fix — bug → červený test → oprava → zelená

Argument: `$ARGUMENTS`. Komunikuj po slovensky.

## 0. Vstup

- Obsahuje `--unlock` → spusti len toto, vypíš jeho riadok a skonči:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-lock.sh" unlock --project "${CLAUDE_PROJECT_DIR}"
```

- Prázdny → jedna otázka: čo robíš, čo čakáš, čo sa stane namiesto toho.
- Len pre pokazené správanie. Zámerná zmena správania alebo nová funkcia → bežný postup (plan mode, `/dev:test`).

## 1. Fakty pred zásahom (žiadne edity)

- **Kde**: miesto chyby `súbor:riadok` (stack trace, log, `grep -rn` hlášky).
- **Kto volá**: volajúci a cesty, ktoré k chybe vedú.
- **Dáta**: konkrétny vstup, ktorý chybu vyvolá; očakávané vs. skutočné.
- **Príčina**: jedna veta, overená čítaním kódu alebo behom — nehádaj.
- Zmena v jadre (validácia vstupov, DB triggery, verejné API, migrácie) → najprv skill `ecc-change-impact`.
- Dodrž pravidlá projektu (CLAUDE.md, `.claude/rules/`) k testom a rozsahu.
- Príčina nejasná → povedz, čo chýba (log, dáta, prístup), a spýtaj sa. Žiadna oprava naslepo.

## 2. Červený regresný test

- Spustenie `/dev:fix` je súhlas s regresným testom; znova sa naň nepýtaj.
- Najnižšia úroveň, ktorá bug ukáže: unit → integračný (DB) → E2E (len UI). Drž konvencie existujúcich testov (base triedy, umiestnenie, pomenovanie).
- Názov opisuje bug: `testRejectsEmptyPinInsteadOfCrashing`, pytest `test_rejects_empty_pin`.
- Spusti len tento test:
  - príkaz kroku `unit`/`integration` z `check.steps[].run` v `.claude/devkit.json`; `--testsuite <x>` nahraď cestou k testu + `--filter <metóda>`; pytest `pytest -q <súbor>::<test>`
  - s `container` → `docker exec -i -w <appRoot> <container> sh -c '<príkaz>'` (vo worktree `appRoot/<cesta voči hlavnému repu>`), nikdy `-it`
  - bez devkit.json → zjavný príkaz projektu (CLAUDE.md, `Makefile`, `vendor/bin/phpunit`, `pytest`)
- Musí padnúť **na asercii, ktorá popisuje bug** — nie parse error ani chyba setupu. Riadok výsledku si zapamätaj (RED dôkaz).
- Testom sa reprodukovať nedá (konfigurácia, infra, dáta prostredia) → povedz prečo, opíš ručný repro a pokračuj bez zámku; vo výstupe netvrď „overené testom".

## 3. Zámok testu

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-lock.sh" lock <cesta/k/Testu.php> --project "${CLAUDE_PROJECT_DIR}"
```

- Cesta relatívna ku koreňu projektu; zámok vyprší sám (predvolene 6 h).
- Bez `.claude/devkit.json` hooky nebežia a zámok len informuje — pravidlo needitovať test platí rovnako.
- Odteraz test needituj — ani cez Bash (`sed`, presmerovanie, `cp`, `git checkout`). Hook edit odmietne.
- Test nevypínaj ani inde: `markTestSkipped`/`pytest.skip`, vyradenie v `phpunit.xml*`/`conftest.py`, `check.knownFailures`, `disabledRules`.
- Ukáže sa, že je zlý samotný test → zastav a vysvetli prečo. Odomknúť môže len používateľ (`/dev:fix --unlock`); sám spúšťaš `test-lock.sh unlock` len po zelenej kontrole v §4.

## 4. Oprava

- Najmenšia zmena produkčného kódu, ktorá odstráni príčinu, nie symptóm. Zvyšok systému správaj rovnako ako doteraz.
- Priľahlé edge cases a „keď už som tu" úpravy neopravuj — zapíš ich ako follow-up. Novú podmienku či kontrolu mimo zadania najprv navrhni a opýtaj sa.
- Repro test → zelený (GREEN dôkaz).
- Celá kontrola (Bash timeout 600000 ms):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/check.sh" --auto --project "${CLAUDE_PROJECT_DIR}"
```

- `1` FAIL → oprav kód (nie test) a zopakuj; zlyhania mimo tvojich zmien len nahlás. Po 2 neúspešných kolách zastav, nahlás stav (čo padá, hypotéza) a navrhni /clear s presnejším zadaním; test ostáva zamknutý.
- `3` bez devkit.json → spusti celú unit sadu zjavným príkazom projektu; zelená → odomkni ako pri `0`. Spomeň `/dev:project-init`.
- `4` nič nebežalo → nahlás dôvod (kontajner, nástroje), PASS netvrď, test nechaj zamknutý.
- `0` PASS → odomkni:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-lock.sh" unlock --project "${CLAUDE_PROJECT_DIR}"
```

## 5. Výstup

- Príčina: `súbor:riadok` — jedna veta
- Oprava: `súbor:riadok` — čo sa zmenilo
- Test: `tests/…Test.php::metóda`
- RED → GREEN: `<riadok z behu>` → `<riadok z behu>`
- `check auto: PASS · …` (alebo prečo nie)
- Follow-up: čo si zámerne neopravil (len ak niečo je)
- Ďalej: `/dev:review`, potom `/dev:commit`. Sám necommituj.
