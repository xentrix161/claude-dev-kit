---
name: check
description: "Overí zmeny projektu jedným príkazom (PHPStan, testy, phpcs, latte… podľa .claude/devkit.json) a vráti PASS/FAIL s nálezmi. Zelený beh odomkne commit gate pre aktuálny obsah."
argument-hint: "[--quick|--full|--auto] [--files <súbor>…]"
disable-model-invocation: true
allowed-tools:
  - 'Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/check.sh" *)'
---
<!-- postup overovania z ECC skills/verification-loop @ b92f181, výsledok výhradne zo scripts/check.sh -->

# /dev:check — overenie zmien

Jediný zdroj pravdy je `check.sh`. PASS tvrď len podľa jeho výstupu a exit kódu z tohto ťahu. Komunikuj po slovensky.

## 1. Spustenie

- Argumenty: `$ARGUMENTS` (prázdne = `--quick`).
- Skriptu odovzdaj len `--quick`, `--full`, `--auto` a `--files <rel>…` (cesty relatívne ku koreňu projektu). Slová bez pomlčky prelož (`full` → `--full`). Ostatný text ber ako pokyn používateľa, nie ako argument skriptu.
- Režimy: `--quick` = rýchle kroky nad zmenenými súbormi · `--full` = aj pomalé sady (integračné testy) · `--auto` = `--full`, keď zmena zasahuje `check.fullWhen`, inak `--quick`.
- Spusti presne takto, bez `cd`, bez `| tail` (exit kód musí ostať skriptu); `--project` vždy pred prepínačmi, `--files <rel>…` na koniec:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/check.sh" --project "${CLAUDE_PROJECT_DIR}" <prepínače>
```

- Bash timeout: `--quick` 300000 ms, `--full` a `--auto` 600000 ms.

## 2. Exit kód

| kód | význam | čo urobiť |
|---|---|---|
| 0 | PASS | výstup podľa §5; commit gate je odomknutý pre aktuálny obsah súborov |
| 1 | FAIL | rozbor podľa §3 |
| 3 | chýba alebo je chybný `.claude/devkit.json` | §4 |
| 4 | neúplné overenie: `PARTIAL` (krok sa nedal spustiť) alebo `SKIP` (nič nebežalo) | vypíš dôvody z riadkov `!` a `–`; nikdy netvrď PASS; commit gate ostáva zamknutý |
| iný | chyba skriptu | ukáž výstup, nehádaj; detail v `${DEVKIT_DATA:-$HOME/.claude/dev-kit}/errors.log` |

Pri kóde 4:
- `! <krok>: príkaz sa nedá spustiť` alebo `chyba prostredia` → nástroj alebo prostredie chýba; povedz, ktorý krok neprebehol.
- `kontajner <c> nebeží` → navrhni spustenie (napr. `make start`, `docker compose up -d`). Kontajnery sám nespúšťaj, nereštartuj ani nezastavuj.
- `chýba <cesta>` → nástroj nie je nainštalovaný (`composer install`, venv).
- `žiadne zmenené súbory` → nie je čo overiť.
- `worktree mimo mountu kontajnera` → worktree nie je pod koreňom repa, ktorý kontajner mountuje.
- `príkaz sa nedá spustiť (exit 126/127)` → príkaz z `devkit.json` neexistuje alebo nie je spustiteľný; navrhni opravu `run`/`runFiles`.
- `chyba prostredia, nie kódu (…)` → zlyhal docker alebo nástroj, nie kód; cituj hlásenie.
- `žiadne kroky pre režim <režim>` → žiadny krok nemá tento režim v `modes`.

## 3. FAIL — rozbor

- Zdroj: riadky pod `✗ <krok>`. Ak nestačia, hľadaj v logu z riadku `log: <cesta>` cez `grep -n` (názov kroku, súbor, `FAIL`, `Error`). Celý log nečítaj.
- Z výstupu vyrob nálezy `súbor:riadok — chyba`:
  - PHPStan raw: `cesta:riadok:správa`
  - phpcs emacs: `cesta:riadok:stĺpec: error - správa`
  - PHPUnit: `N) Trieda::metóda` + prvý riadok stopy v projekte `/…/Súbor.php:123`
  - pytest: `FAILED cesta::test` + riadok `cesta:riadok:` z tracebacku
  - cesty z kontajnera (`<appRoot>/…`) preveď na relatívne k repu
- Každý nález over v kóde (prečítaj okolie riadku) ešte pred nahlásením.
- Zlyhanie v súbore, ktorý táto úloha nemenila, označ `mimo tvojich zmien` (legacy alebo rozrobená práca inej session).
- Poradie opráv: syntax/parse → statická analýza (typy) → unit testy → integračné → štýl (phpcs). Príčina pred následkom: jedna chyba často zhodí ďalšie kroky.
- Opakované zlyhanie mimo tvojich zmien navrhni do `check.knownFailures` — zapísať len so súhlasom. Neoveruj ho cez `git stash` ani prepnutím vetvy (v repe môžu pracovať iné sessions).
- Bez pokynu neopravuj. Keď používateľ opravu žiada, oprav v navrhnutom poradí a spusti rovnaký príkaz znova (max 2 kolá, potom nahlás stav a navrhni /clear s presnejším zadaním).
- Stop hook môže po FAIL zablokovať koniec ťahu (najviac 2×); keď čakáš na súhlas používateľa s opravou, ukonči ťah jednou vetou so stavom.

## 4. Bez `.claude/devkit.json`

- Povedz jednou vetou: projekt nemá `.claude/devkit.json` → `/dev:project-init` ho nastaví; dovtedy nebeží Stop kontrola ani commit gate.
- Chybný JSON → `jq . .claude/devkit.json` ukáže miesto chyby.
- Náhradná kontrola (len čítajúce príkazy), ak chce používateľ výsledok hneď:
  - príkazy nájdi v CLAUDE.md projektu, `Makefile`, `composer.json` (`scripts`), `pyproject.toml`
  - PHP: `vendor/bin/phpstan analyse`, `vendor/bin/phpunit`, `vendor/bin/phpcs`; Python: `pytest -q`, `ruff check .`, `mypy`
  - projekt v Dockeri (`docker-compose*.yml`, `compose*.yml`) → `docker exec <kontajner> …` bez `-it`; make ciele s `-it` bez TTY padnú
  - vo výstupe uveď `bez devkit.json — marker pre commit sa nezapisuje`

## 5. Výstup

- Prvý riadok = verdikt zo skriptu: `check <režim>: PASS|FAIL|PARTIAL|SKIP · N ok · N fail · N skip · N s` (pri známych zlyhaniach aj `· N známe`).
- Preskočené kroky vždy spomeň s dôvodom: `!` = nedal sa spustiť (overenie neúplné), `–` = netýka sa zmien.
- FAIL: všetky nálezy z výstupu a logu, číslované `N. súbor:riadok — chyba (krok)`, potom `Poradie opráv: 2 → 1 → 3` a jednou-dvoma vetami prečo.
- Posledný riadok `log: <cesta>`.
- FAIL bez pokynu na opravu ukonči jednou otázkou: „Opraviť v tomto poradí?"
- Bez úvodu a bez záverečného zhrnutia; vysvetlenie v krátkych odsekoch celých viet, keď ho výsledok potrebuje.
