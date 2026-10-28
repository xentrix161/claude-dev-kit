---
name: debug
description: "Ladenie chyby v appke krok za krokom: fakty z logov (Tracy, var/log, traceback, docker logs), hypotéza, minimálna reprodukcia, návrh opravy. Nette, Symfony, Python. Nikdy nehádať."
argument-hint: "<popis chyby | URL | test | text výnimky>"
disable-model-invocation: true
---

# Debug

Systematické hľadanie príčiny chyby v appke. Po slovensky, stručne, ale úplne: záver prvý, potom podklady. Vstup: `$ARGUMENTS`
Prázdny vstup → opýtaj sa: „Čo presne nefunguje? URL/akcia/test, čo čakáš a čo sa stane."

## Zásady

- **Nikdy nehádaj.** Každé tvrdenie o príčine opri o výstup príkazu alebo `súbor:riadok`; inak ho označ „hypotéza".
- **Najprv diagnostika.** Kód neopravuj, kým nie je príčina potvrdená a používateľ to nechce; opravu robí `/dev:fix` (repro test + zámok testu).
- **Zdieľané prostredie.** Kontajnery nereštartuj, DB neimportuj, dáta nemeň, cache nemaž bez súhlasu — nad projektom môžu bežať iné sessions.
- **Bez debug kódu v repe.** `dump`, `bdump`, `var_dump`, `print` do zdrojákov nepíš (hook ich zablokuje); použi test, `php -r` / `python -c` v kontajneri alebo log.
- **Credentials** (`.test-credentials`, `config.local.*`, `.env*`, API kľúče) nikdy nevypisuj.
- **Po 2 neúspešných pokusoch** o opravu zastav, zhrň zistené fakty a navrhni `/clear` s presnejším zadaním.

## Prostredie

- `.claude/devkit.json` → `stack`, `container`, `appRoot`. Bez neho: stack z `composer.json` (nette/symfony) / `pyproject.toml`, príkazy na hostiteľovi.
- S kontajnerom: `docker exec -i -w <workdir> <container> sh -c '<príkaz>'` — nikdy `-it`.
  - workdir = `appRoot`; vo worktree `appRoot/<cesta worktree relatívne k hlavnému repu>`
- Kontajner nebeží (`docker inspect -f '{{.State.Running}}' <container>`) → povedz to; spustiť len so súhlasom.
- Cesty v logoch z kontajnera (`<appRoot>/…`) prevádzaj na cesty v repe.

## Postup

1. **Fakty** — presný symptóm (hláška, URL/akcia/príkaz, kedy, opakovateľné?) a čo sa nedávno zmenilo: `git log --oneline -10`, `git status --short`, `git diff --stat`.
2. **Logy a stav** podľa stacku (nižšie) — najnovšie záznamy okolo času symptómu.
3. **Hypotézy** — najviac 3, zoradené podľa dôkazov; ku každej lacný test s očakávaným výsledkom. Začni najlacnejším.
4. **Minimálna reprodukcia** — najlepšie padajúci test (PHPUnit/pytest), inak `curl` request alebo CLI príkaz. Spusti a over, že padá z očakávaného dôvodu.
5. **Návrh opravy** — každý krok opravy so `súbor:riadok`; implementácia cez `/dev:fix` alebo na pokyn.

Tiché zlyhanie (nič sa nestane, žiadna chyba) → agent `dev:ecc-silent-failure-hunter`. Pomalosť → agent `dev:ecc-performance-optimizer` + `EXPLAIN` (skill `ecc-mysql-patterns`). Ich nálezy over sám.

## Nette

- **Tracy**: `command ls -t log/*.html | head -5` (`exception--*`, `error--*`; `command` obíde alias `ls`, ktorý mení poradie). Súbor má stovky KB — nečítaj ho celý:
  - hláška: `grep -o '<title>[^<]*' <súbor>`
  - stack len z projektu: `grep -o 'title="[^"]*:[0-9]*"' <súbor> | grep -v /vendor/ | head`
- `tail -n 30 log/exception.log log/error.log` — riadok končí `@@ <html súbor>`; ďalšie `log/*.log`
- `docker logs --since 15m <container> 2>&1 | tail -n 80` (PHP-FPM; nginx kontajner rovnako)
- DI/config chyba (`ServiceCreationException`, `InvalidConfigurationException`) → neon config a lokálny override; zastaraná `temp/cache` (Latte, DI kontajner) — mazať len so súhlasom
- Latte: `php vendor/bin/latte-lint <súbor>`
- **Mail**: Mailpit (služba `mailpit` v docker compose) — `curl -s 'http://localhost:<port>/api/v1/messages?limit=5'`, web UI na tom istom porte
- **Typesense**: `curl -s http://localhost:<port>/health` → `{"ok":true}`; kolekcie s API kľúčom z lokálneho configu (kľúč nevypisuj)
- **Overenie v appke**: prihlás sa údajmi z `.test-credentials` (Chrome MCP alebo `curl -c/-b` s cookie jar) a testuj priamo v appke, nestavaj izolované repro stránky; súbor nečítaj ani nevypisuj; v jednom Bash volaní: `set -a; . ./.test-credentials; set +a; curl -c jar … --data-urlencode "password=$APP_TEST_PASS"` — v texte príkazu len mená premenných (mená podľa súboru projektu, napr. z jeho `.stub`)
- **DB**: `EXPLAIN <SELECT>` cez MySQL klienta v DB kontajneri — len čítanie (`SELECT`, `EXPLAIN`, `SHOW`)
- **Frontend**: konzola a sieť cez Chrome MCP; jQuery na prázdnej kolekcii nehádže → over selektor (`$('.trieda').length`)

## Symfony

- `tail -n 50 var/log/dev.log` (prod: `var/log/prod.log`), hľadaj `request.CRITICAL` / `ERROR`
- profiler: `curl -sI <url>` → hlavička `X-Debug-Token-Link` → `/_profiler/<token>` (výnimka, dotazy, logy)
- `bin/console debug:router` / `router:match <cesta>`, `debug:container <id>`, `debug:autowiring <typ>`, `debug:config <bundle>`, `debug:event-dispatcher <event>`, `debug:messenger`
- `bin/console lint:container`, `lint:twig`, `lint:yaml config`, `doctrine:schema:validate`
- `bin/console cache:clear` len so súhlasom

## Python

- traceback čítaj odspodu: posledný rámec v kóde projektu = miesto chyby, nad ním volajúci
- `pytest -x -q --lf` (najprv naposledy padajúce), `pytest -x -vv <súbor>::<test>`, `--log-cli-level=DEBUG`
- `python -X dev` (skryté varovania, ResourceWarning); verzie balíkov `pip list` / `uv pip list`
- Django `manage.py check`; logy servera (uvicorn/gunicorn) cez `docker logs`

## Výstup

- `Príčina:` jedna veta + `súbor:riadok` — alebo `Príčina nepotvrdená:` najsilnejšia hypotéza
- `Dôkaz:` príkaz + kľúčový riadok výstupu
- `Repro:` test alebo príkaz (ak existuje)
- `Oprava:` každý krok opravy so `súbor:riadok`
- `Ďalej:` `/dev:fix <popis>` alebo jedna konkrétna otázka na používateľa
