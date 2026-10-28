---
paths:
  - "tests/**"
  - "**/test_*.py"
  - "**/*_test.py"
  - "**/conftest.py"
---

# Testy (pytest)

- Konfigurácia v `pyproject.toml` `[tool.pytest.ini_options]` (alebo `pytest.ini`); markery registrované, `--strict-markers`.
- Rýchle testy (`/dev:check`, Stop) = `pytest -q -m "not slow and not integration"` → pomalé a integračné testy označ markerom `slow` / `integration`.
- Všetky testy: `/dev:check --full`.
- Štruktúra zrkadlí kód: `src/<balík>/billing/invoice.py` → `tests/unit/billing/test_invoice.py`.
- Názov `test_<čo>_<keď>_<výsledok>`; jeden test = jedno správanie; Arrange · Act · Assert oddelené prázdnym riadkom.
- Fixtures v najbližšom `conftest.py`; setup/teardown cez `yield`; vstavané `tmp_path`, `monkeypatch`, `caplog`, `capsys`.
- Testy nezávislé od poradia; meniteľné dáta len vo fixture so `scope="function"`.
- DB testy v transakcii s rollbackom (alebo `pytest-django` `db`); testovacia DB oddelená od vývojovej.
- Bez reálnej siete, mailu a platieb: mock na hranici (HTTP klient, čas, mail) s `autospec=True`; HTTP cez `respx` / `responses`.
- Čas zmraz (`freezegun`, `time-machine`) alebo vstrekni hodiny; `sleep` na čakanie nie.
- Oprava bugu: najprv test, ktorý padá z očakávaného dôvodu (`/dev:fix` ho zamkne), až potom kód.
- Padajúci test neoslabuj; `skip`/`xfail` len s dôvodom (`reason=`) a so súhlasom používateľa; `xfail(strict=True)`.
- Pokrytie (`--cov`) len na orientáciu, bez percentuálnych cieľov.
- Žiadne produkčné ani skutočné osobné dáta vo fixtures.

## Overenie

- Hlás skutočný výstup: `N passed in X s` alebo `FAILED tests/…::test_x - <príčina>`; nikdy „testy prejdú" bez behu.
- Jeden test `pytest -x -q tests/…::test_y`; posledné zlyhané `pytest --lf -q`; detail `-vv --tb=long`.
- Príkaz s prefixom z `.claude/devkit.json` (`.venv/bin/pytest`, `docker exec -w <workdir> <kontajner> pytest`).

## Pasce

- Exit kód 5 = nevybrali sa žiadne testy (zlý `-m`, `-k` alebo cesta) — nie je to PASS.
- `patch("modul.meno")` mieri tam, kde sa meno **používa**, nie kde je definované.
- `mock.called_once_with(...)` bez `assert_` pod Python 3.12 vždy prejde → `assert_called_once_with` a `autospec=True`.
- Rovnaký názov test súboru v dvoch adresároch bez `__init__.py` → „import file mismatch"; pridaj `__init__.py` alebo `--import-mode=importlib`.
- Fixture so `scope="session"`/`"module"` a meniteľnými dátami prenáša stav → testy závislé od poradia.
- Float porovnaj cez `pytest.approx`, nie `==`.
- `async def` test bez pytest-asyncio/anyio (`@pytest.mark.asyncio` alebo `asyncio_mode = "auto"`) sa nevykoná — skip s varovaním alebo chyba.
- Fixture rovnakého mena v podadresári tieni nadradenú — over `pytest --fixtures`.
- Test bez asercie dokazuje len, že kód nespadol.
