---
name: ecc-python-testing
description: "pytest: fixtures, parametrize, markery, mocky s autospec, async testy, tmp_path a izolácia DB. Použi pri písaní, oprave alebo review Python testov."
paths:
  - "tests/**/*.py"
  - "**/test_*.py"
  - "**/*_test.py"
---
<!-- prevzaté z ECC skills/python-testing/SKILL.md @ 25278e7d, upravené -->

# Python testy (pytest)

- Prednosť má projekt: `CLAUDE.md`, `.claude/rules/tests.md`, `[tool.pytest.ini_options]` v `pyproject.toml`, existujúce `conftest.py`.
- Postup RED → GREEN → REFACTOR vedie `/dev:test`; oprava bugu s reprodukčným testom `/dev:fix`.
- Spúšťaj s prefixom z `.claude/devkit.json` (`.venv/bin/pytest …` alebo `docker exec -i -w <workdir> <kontajner> pytest …`); celok overí `/dev:check`.
- Do odpovede len skutočný výstup: `N passed in X s` alebo `FAILED <node id> - <príčina>`.

## Cyklus s dôkazom

1. RED: test na požadované správanie; spusti ho a over, že padá **z očakávaného dôvodu** (nie ImportError ani preklep).
2. GREEN: minimálna zmena kódu; zelený test aj okolité testy.
3. REFACTOR: uprac kód aj test, testy ostávajú zelené.
- Padajúci test neoslabuj, nemaž asercie, neskipuj — oprav kód. Zlý test meň len so súhlasom a povedz prečo.

## Štruktúra a pomenovanie

- Zrkadli kód: `src/app/billing/invoice.py` → `tests/unit/billing/test_invoice.py`.
- `test_<čo>_<keď>_<výsledok>`: `test_total_with_discount_rounds_half_up`.
- Arrange · Act · Assert oddelené prázdnym riadkom; jeden test = jedno správanie.
- Súvisiace testy v triede `TestX` (bez `__init__`), spoločný setup cez fixture.

```python
def test_total_with_discount_rounds_half_up(invoice_factory):
    invoice = invoice_factory(items=[Decimal("10.005")], discount=Decimal("0.1"))

    total = invoice.total()

    assert total == Decimal("9.00")
```

## Asercie

- Čisté `assert` — pytest ukáže rozdiel; porovnávaj celé štruktúry (`assert result == {...}`), nie pole po poli.
- Výnimka: `with pytest.raises(ValidationError, match="email"):`; detaily cez `exc_info.value`.
- Float `pytest.approx`; `None` a bool cez `is`.
- Varovania `pytest.warns(DeprecationWarning)`; logy `caplog.records`, výstup `capsys.readouterr()`.

## Fixtures

```python
@pytest.fixture
def user_factory(db_session):
    def make(**overrides) -> User:
        user = User(**{"email": "a@example.com", "is_active": True, **overrides})
        db_session.add(user)
        db_session.flush()
        return user
    return make
```

- Setup a teardown cez `yield` vo fixture, nie ručné upratovanie v teste.
- Scope `function` (predvolený) pre meniteľné dáta; `session`/`module` len pre drahé a nemenné zdroje (engine, klient).
- Zdieľané fixtures v najbližšom `conftest.py`; neimportuj fixture z iného test modulu.
- Vstavané: `tmp_path` (nie `tmpdir`), `monkeypatch` (env, atribúty, `chdir`), `caplog`, `capsys`.
- Factory fixture namiesto desiatok fixtures pre varianty; `autouse=True` šetrne — skrytá závislosť každého testu.

## Parametrizácia

```python
@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        pytest.param("a@b.sk", True, id="platny"),
        pytest.param("bez-zavinaca", False, id="chyba-zavinac"),
        pytest.param("", False, id="prazdny"),
    ],
)
def test_is_valid_email(raw: str, expected: bool) -> None:
    assert is_valid_email(raw) is expected
```

- `id=` pre čitateľný výstup; hraničné prípady: prázdne, `None`, hranice intervalu, diakritika a unicode.
- Známa chyba: `pytest.param(..., marks=pytest.mark.xfail(strict=True, reason="…"))`.

## Markery a výber

```toml
[tool.pytest.ini_options]
addopts = ["--strict-markers"]
markers = ["integration: potrebuje DB alebo službu", "slow: beží dlhšie ako ~1 s"]
```

- `--strict-markers` → preklep v markeri je chyba, nie tichý výber.
- Rýchla kontrola kitu (`/dev:check`, Stop) spúšťa `-m "not slow and not integration"` — pomalé a integračné testy označ, inak brzdia každý ťah.
- `skipif(podmienka, reason="…")`; `xfail(strict=True)`, aby oprava neprešla nepovšimnutá.

## Mocky

- Mockuj hranicu systému (HTTP, čas, mail, platby, súborový systém), nie vlastnú logiku.
- `patch` cieľ = modul, kde sa meno **používa**: `patch("app.services.billing.send_mail")`, nie `app.mail.send_mail`.
- `autospec=True` / `create_autospec` → zlé meno metódy alebo argumenty padnú.
- Interakciu over presne: `assert_called_once_with(...)`; chyby simuluj `side_effect = TimeoutError()`.
- Async: `AsyncMock`, `assert_awaited_once_with`.
- Env a atribúty jednoduchšie cez `monkeypatch.setenv` / `monkeypatch.setattr`.
- HTTP knižnice: `respx` (httpx), `responses` (requests) namiesto ručného mocku.

```python
def test_notify_overdue_sends_one_mail(monkeypatch):
    sent: list[str] = []
    monkeypatch.setattr("app.services.notify.send_mail", lambda to, body: sent.append(to))

    notify_overdue(invoice_id=7)

    assert sent == ["a@example.com"]
```

## Async

- pytest-asyncio: `@pytest.mark.asyncio` alebo `asyncio_mode = "auto"`; anyio: `@pytest.mark.anyio`.
- Async fixture s `yield` pre klienta, napr. `httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test")`.
- `ASGITransport` nespúšťa lifespan udalosti: ak má aplikácia startup/shutdown handlery, obal ju do `asgi_lifespan.LifespanManager` a fixture označ `@pytest_asyncio.fixture`.
- Bez pluginu sa `async def` test nevykoná (skip s varovaním alebo chyba podľa verzie pytestu).

## DB a externé služby

- Každý test v transakcii s rollbackom: SQLAlchemy `connection.begin()` + `Session(bind=connection, join_transaction_mode="create_savepoint")`; Django `pytest-django` (`db` fixture) alebo `TestCase`.
- Testovacia DB oddelená od vývojovej; žiadne produkčné ani skutočné osobné dáta vo fixtures.
- Žiadna reálna sieť ani mail; čas zmraziť (`freezegun`, `time-machine`) alebo vstreknúť hodiny; `sleep` na čakanie nie.

## Spúšťanie

| Účel | Príkaz |
|---|---|
| jeden test | `pytest -x -q tests/unit/test_x.py::test_y` |
| posledné zlyhané | `pytest --lf -q` |
| podľa mena | `pytest -q -k "invoice and not slow"` |
| podľa markera | `pytest -q -m integration` |
| detail zlyhania | `pytest -x -vv --tb=long tests/…` |
| pokrytie | `pytest --cov=<balík> --cov-report=term-missing` (orientačne, bez % cieľa) |

- `--pdb` len v termináli používateľa — v hooku ani v Bash nástroji nie (čaká na vstup).

## Pasce

- Exit kód 5 = nevybrali sa žiadne testy (zlý `-m`, `-k` alebo cesta) — nie je to PASS.
- `mock.called_once_with(...)` bez `assert_` pod Python 3.12 vždy prejde → `assert_called_once_with` a `autospec=True`.
- Rovnaký názov test súboru v dvoch adresároch bez `__init__.py` → „import file mismatch"; `__init__.py` alebo `--import-mode=importlib`.
- Fixture so `scope="session"`/`"module"` a meniteľnými dátami prenáša stav → testy závislé od poradia.
- `datetime.now()` / `date.today()` bez zmrazenia → test padá okolo polnoci a pri zmene času.
- Fixture rovnakého mena v podadresári tieni nadradenú — over `pytest --fixtures`.
- Test bez asercie dokazuje len, že kód nespadol.
