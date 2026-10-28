---
name: test
description: "Napíše testy pre triedu, súbor alebo nové správanie cez RED → GREEN → REFACTOR s dôkazom z behu (PHPUnit, Nette Tester, pytest) podľa konvencií projektu."
argument-hint: "[súbor|trieda|správanie] [--coverage]"
disable-model-invocation: true
allowed-tools:
  - 'Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/check.sh" *)'
---
<!-- základ ~/.claude/commands/test.md + RED/GREEN evidencia z ECC skills/tdd-workflow @ b92f181, upravené -->

# /dev:test — testy s dôkazom

„Test padá / prechádza" tvrď len s výstupom behu z tohto ťahu. Komunikuj po slovensky.

## 1. Cieľ a režim

- Argument: `$ARGUMENTS`. Prázdny → spýtaj sa: „Pre ktorú triedu/súbor alebo aké správanie chceš testy?"
- **A — nové alebo menené správanie** → plné TDD: test pred kódom (RED → GREEN → REFACTOR).
- **B — testy k existujúcemu kódu** → charakterizačné testy majú prejsť hneď; padajúci test je zlý test alebo nájdený bug. Bug nahlás `súbor:riadok` a kód potichu neopravuj.
- Pokazené správanie s opravou → odporuč `/dev:fix` (repro test + zámok testu).

## 2. Analýza

- Prečítaj cieľ celý: verejné metódy, správanie, závislosti (konštruktor, DI, traity), výnimky.
- Stack: `stack` v `.claude/devkit.json`, inak `composer.json` (nette/symfony, verzia phpunit) / `pyproject.toml`.
- Existujúce testy cieľa (`grep -rl <Trieda> tests/`) — dopĺňaj, neduplikuj.
- Konvencie projektu: base triedy (`*TestCase`), suity v `phpunit.xml*`, pomenovanie, `declare(strict_types=1)` len ak ho testy projektu majú.
- Umiestnenie: zrkadlová štruktúra pod `tests/` podľa existujúcich testov, trieda `{Trieda}Test`.
- Typ: unit (bez DB) kde sa dá; integračný, keď správanie stojí na DB a projekt má base triedu s transakciou a rollbackom; E2E len pre čisto UI správanie.

## 3. Prípady

- 3–8 prípadov: happy path, hraničné hodnoty (null, prázdne, 0, max), chybové cesty a výnimky. V režime B má každá verejná metóda s logikou aspoň jeden test.
- Názov opisuje správanie: `testReturnsNullWhenRecordMissing`, pytest `test_returns_none_when_record_missing`.
- AAA: Arrange / Act / Assert, jeden dôvod zlyhania na test, testy nezávislé od poradia.
- Netestuj: private/protected priamo, triviálne gettre/settre, framework.
- Mocky: `createMock`/`createStub` (PHPUnit) pre služby a repozitáre, fixtures a `monkeypatch` (pytest). Nepremockovať — hodnotové objekty použi skutočné.
- Externé služby (mail, SMS, HTTP API) nikdy naostro — použi test doubles, ktoré projekt už má.

Vetvy podľa stacku:
- **PHPUnit 10+**: atribúty `#[Test]`, `#[DataProvider('…')]`; anotácie len v starších verziách (`vendor/bin/phpunit --version`).
- **Nette**: služby z DI kontajnera cez base triedu projektu; presenter testy podľa existujúcich (napr. `createPresenter()`); Nette Tester (`*.phpt`) → `vendor/bin/tester <súbor>`.
- **Symfony**: `KernelTestCase` (služby), `WebTestCase` (HTTP); izolácia DB mechanizmom, ktorý projekt už používa.
- **pytest**: fixtures v `conftest.py`, `@pytest.mark.parametrize` pre tabuľku prípadov, `tmp_path`, bez siete.

## 4. Spustenie len nových testov

- S `.claude/devkit.json`: príkaz kroku `unit`/`integration` z `check.steps[].run`. Pre jeden test nahraď `--testsuite <x>` cestou k testu a pridaj `--filter <metóda>`; pytest `pytest -q <súbor>::<test>`.
- `container` nastavený → `docker exec -i -w <workdir> <container> sh -c '<príkaz>'`:
  - `workdir` = `appRoot`; vo worktree `appRoot/<cesta worktree voči hlavnému repu>` (hlavné repo: `git rev-parse --path-format=absolute --git-common-dir` bez `/.git`)
  - nikdy `-it` (bez TTY padne)
- Bez `container` → príkaz priamo v koreni projektu.
- Bez `.claude/devkit.json` → zjavný príkaz projektu (CLAUDE.md, `Makefile`, `composer.json` scripts, `vendor/bin/phpunit`, `pytest`); spomeň `/dev:project-init`.

## 5. Cyklus

Režim A:
1. **RED** — napíš test, spusti len ho. Musí padnúť na očakávanej asercii alebo na chýbajúcej triede/metóde, ktorú test volá. Parse error, chyba setupu či nedostupná DB nie sú RED → oprav test a spusti znova. Produkčný kód needituj, kým RED nie je potvrdený.
2. **GREEN** — najmenšia zmena produkčného kódu; ten istý príkaz → zelené.
3. **REFACTOR** — uprac kód aj test, beh ostáva zelený.

Režim B: napíš testy, spusti; zelené = hotovo. Červené → rozhodni, či je zlý test (oprav ho) alebo bug (nahlás, navrhni `/dev:fix`).

Na záver statická analýza a štýl aj pre nové testy (Bash timeout 300000 ms):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/check.sh" --quick --project "${CLAUDE_PROJECT_DIR}"
```

Exit 3 = bez devkit.json (preskoč s poznámkou), 4 = nič nebežalo (uveď dôvod), 1 = oprav nálezy v nových a zmenených súboroch a zopakuj; zlyhania mimo tvojich zmien len nahlás.

Necommituj — commit ide cez `/dev:commit`.

## UI zmena

Zmena šablón, CSS alebo JS → over ju aj v bežiacej appke vstavaným `/verify` alebo cez Chrome MCP. Prihlás sa testovacími údajmi projektu a nikdy ich nevypisuj (postup v skille `debug`, „Overenie v appke“). Kontrolný zoznam:
- stránka vráti 200 (nie presmerovanie na login)
- konzola bez chýb
- formulár sa odošle a uloží
- JS kotvy (`data-*` atribúty, triedy, na ktorých visí JS) fungujú
- po zmene CSS hard reload (cache)

## 6. `--coverage`

- PHPUnit: príkaz z §4 + `--coverage-text` (potrebuje Xdebug alebo PCOV; bez nich to povedz a skonči).
- pytest: `pytest --cov=<balík> --cov-report=term-missing <súbor>`.
- Nahlás len nepokryté riadky cieľa (`súbor:riadok-riadok`); žiadne percentuálne ciele.

## 7. Výstup

- `tests/…/XTest.php` — N testov, prípady jedným riadkom
- RED: `<príkaz>` → `<riadok výsledku>` (len režim A)
- GREEN: `<príkaz>` → `<riadok výsledku, napr. OK (5 tests, 9 assertions)>`
- `check quick: PASS|FAIL` (alebo dôvod, prečo nebežal)
- UI zmena: čo si overil v appke, alebo „v appke neoverené“
- nájdené bugy / nepokryté miesta: `súbor:riadok — výstih`
- ďalej: `/dev:review`, `/dev:commit`
