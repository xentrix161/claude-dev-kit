---
name: deps
description: "Aktualizácia jednej závislosti (Composer, pip, Poetry, uv): zastarané balíky, changelog, update, kontrola, commit."
argument-hint: "[balík]"
disable-model-invocation: true
allowed-tools:
  - 'Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/check.sh" *)'
  - 'Bash(git branch --show-current)'
  - 'Bash(git status *)'
  - 'Bash(git diff *)'
  - 'Bash(git log *)'
---

# /dev:deps — jedna závislosť naraz

Aktualizuje jeden priamy balík: zoznam zastaraných, update, changelog, kontrola a commit súborov závislostí. Nikdy hromadný update. Komunikuj po slovensky. Argumenty: `$ARGUMENTS`

## 1. Projekt

- Správca podľa `stack` v `.claude/devkit.json`: `php-*` → Composer, `python` → podľa súborov nižšie. Iný stack alebo bez configu: `composer.json` → Composer; `uv.lock` → uv; `poetry.lock` → Poetry; `requirements*.txt` → pip (so `requirements*.in` pip-tools). Nejasné (viac správcov, `Pipfile`, `pdm.lock`, nič z toho) → spýtaj sa a skonči.
- Ako spúšťať: príkaz z `CLAUDE.md` projektu (tabuľka Príkazy, wrapper ako `bin/composer` či `make composer`); inak ako krok `audit` v `devkit.json` — s `container` a bez `runtime: host` cez `docker exec -i -w <workdir> <container> <príkaz>` (`workdir` = `appRoot`, vo worktree `appRoot/<cesta voči hlavnému repu>`, nikdy `-it`), inak na hostiteľovi (`composer`, `.venv/bin/pip`, `poetry`, `uv`). Kontajner nebeží → povedz to a skonči; kontajnery nespúšťaj.
- Súbory závislostí už zmenené v pracovnom strome (`git status --short`: `composer.*`, `symfony.lock`, `requirements*`, `pyproject.toml`, `*.lock`) → skonči jednou vetou: aktualizácia ide do samostatného commitu.

## 2. Zoznam

- Composer `composer outdated --direct --format=json`; pip `pip list --outdated --format=json` (len balíky z `requirements*.txt` alebo `pyproject.toml`); Poetry `poetry show --outdated --top-level`; uv `uv pip list --outdated --format=json`. Dotaz ide na Packagist alebo PyPI — kvôli tomu príkaz existuje.
- Zraniteľnosti len keď `devkit.json` má krok `audit` (súhlas s odoslaním zoznamu balíkov dal `/dev:project-init`): jeho príkaz spusti rovnakou cestou s JSON výstupom (`composer audit --locked --format=json`, `pip-audit --format json`). Bez kroku ho nespúšťaj; pod tabuľku daj vetu, že zraniteľnosti nie sú overené (krok navrhne `/dev:project-init --sync`).
- Tabuľka, najviac 15 riadkov, poradie: so zraniteľnosťou, v rámci obmedzenia, mimo neho:

| balík | nainštalovaná | dostupná | druh | poznámka |
|---|---|---|---|---|

  Druh: Composer `latest-status` `semver-safe-update` = v rámci obmedzenia v `composer.json`, `update-possible` = mimo neho (major); Python podľa pinu a verzií. Poznámka: advisory (`CVE-…`, opravené od), `abandoned` s náhradou.
- Argument s menom balíka → otázku preskoč. Balík v zozname nie je → povedz, či je aktuálny, alebo nie je priamou závislosťou, a skonči.
- Bez argumentu jedna otázka „Ktorý balík?“ s možnosťami (AskUserQuestion, ak je dostupný; balík so zraniteľnosťou prvý ako odporúčaný) a koniec ťahu.

## 3. Návrh a jedno potvrdenie

V JEDNEJ správe:
1. Balík a verzia `od → do`. Cieľ: najvyššia verzia v rámci obmedzenia; pri zraniteľnosti najnižšia verzia, ktorá ju opravuje (z advisory), ak je v obmedzení.
2. Príkaz (krok 4). Major mimo obmedzenia → dve možnosti: `v rámci obmedzenia (<verzia>)` alebo `zmena obmedzenia na ^<major>` (`composer require <balík>:^<major> --update-with-dependencies`, `poetry add <balík>@^<major>`; mení manifest).
3. Súbory do commitu a správa (krok 6). Štýl s číslom úlohy a číslo chýba → otázka tu.
4. Changelog: `vendor/` (`site-packages/`) má zatiaľ starú verziu, preto ho prečítaš po update (krok 4). Skôr len z webu a len so súhlasom (WebFetch na `support`/`homepage` balíka v `vendor/<balík>/composer.json` alebo `Project-URL` v `METADATA`).

Počkaj na jedno „ok“. Súhlas v argumente (`schvaľujem`, `bez otázky`) platí ako ok. `permissions.ask` projektu (`composer update|require`) aj tak vypýta povolenie — neobchádzaj ho.

## 4. Update a changelog

- Composer: `composer update <balík> --with-dependencies`; zmena obmedzenia `composer require <balík>:^<major> --update-with-dependencies`. Symfony Flex môže zmeniť `symfony.lock` a recepty — `git status --short` ukáže čo.
- pip s pinom v `requirements*.txt`: uprav pin balíka (`==<verzia>`) a `pip install -r <súbor>`; pip-tools `pip-compile --upgrade-package <balík> <súbor>.in` a `pip-sync`; Poetry `poetry update <balík>`; uv `uv lock --upgrade-package <balík>` a `uv sync`.
- Changelog novej verzie z lokálnych súborov: `vendor/<balík>/` (`UPGRADE*.md`, `CHANGELOG*.md`, `CHANGES*.md`, `RELEASE*`), Python `site-packages/<balík>-<verzia>.dist-info/METADATA`; len sekcie medzi starou a novou verziou. Nič lokálne → WebFetch len so súhlasom, inak „changelog lokálne nie je“.
- Zhrnutie: breaking changes, zmeny správania, zastarané API, nové požiadavky (PHP, Python, rozšírenia). Každé zmenené alebo zastarané API vyhľadaj v kóde projektu (mimo `vendor/`, `.venv/`) → `súbor:riadok`. Nič nevymýšľaj nad rámec changelogu.

## 5. Kontrola

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/check.sh" --full --project "${CLAUDE_PROJECT_DIR}"
```

- Bash timeout 600000 ms.
- PASS a žiadna breaking change nezasahuje kód projektu → krok 6.
- FAIL, PARTIAL, SKIP alebo breaking change v kóde projektu → balík neopravuj ani nevracaj sám. Nahlás nálezy `súbor:riadok` a návrat: `git checkout -- composer.json composer.lock` (aj `symfony.lock`) a `composer install`; Python `git checkout -- <súbory závislostí>` a inštalácia zo zámku. Skonči otázkou: opraviť kód, alebo vrátiť.

## 6. Commit

- Len súbory závislostí, ktoré update zmenil: `composer.json`, `composer.lock`, `symfony.lock`; `requirements*.txt`, `requirements*.in`, `pyproject.toml`, `poetry.lock`, `uv.lock`. Recepty Flex a iné zmeny vymenuj a nechaj necommitnuté.
- Správa podľa pravidla o commitoch projektu ako v `/dev:commit` (riadok `Commit:` v `CLAUDE.md`, číslo úlohy z argumentu alebo vetvy): typ `chore`, výstih `aktualizácia <balík> <od> → <do>`, napr. `[#31] chore: aktualizácia acme/slugify 3.1.0 → 3.2.0`; Jira `ABC-123 Aktualizácia acme/slugify 3.1.0 → 3.2.0`. Jeden riadok.
- `git add <súbory>` (nikdy `-A` ani `.`), `git commit -m "<správa>"`, potom `git log --oneline -1`. Zamietnutie commit gate → postupuj ako `/dev:commit`.

## 7. Výstup

- `<balík> <od> → <do>` a druh.
- Changelog v najviac 6 odrážkach a dopad na projekt `súbor:riadok`; zastarané API, ktoré ešte funguje, navrhni ako ďalšiu úlohu.
- Riadok verdiktu `check.sh` a commit (hash + správa), alebo prečo nevznikol.

## Pravidlá

- NIKDY `composer update` bez mena balíka ani hromadné `pip install -U`, `poetry update`, `uv lock --upgrade` — vždy jeden balík (s jeho závislosťami).
- Jeden balík za beh; ďalší novým `/dev:deps`.
- `composer require` a zmena obmedzenia len po súhlase; `vendor/`, `.venv/` a lock súbory needituj ručne.
- WebFetch len so súhlasom používateľa.
- NIKDY nepushuj, nepoužívaj `--no-verify`, neamenduj; v commite žiadna AI atribúcia.
- Komunikuj po slovensky.
