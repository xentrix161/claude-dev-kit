---
paths:
  - "**/*.py"
  - "**/*.pyi"
---

# Python — základ

- Štýl okolitého kódu a `pyproject.toml` (ruff, mypy) majú prednosť pred osobnými preferenciami.
- Formát rieši `ruff format`; nepreformátovávaj riadky, ktoré nemeníš (diff má ostať čitateľný).
- Drž `requires-python`: žiadna syntax novšej verzie (`X | None` v runtime pod 3.10, `match` pod 3.10, `type X = …` pod 3.12).
- Anotácie na verejných funkciách a metódach vrátane návratového typu; `Any` len na hranici (JSON, netypovaná knižnica).
- `# type: ignore[kód]` len s konkrétnym kódom a dôvodom; mypy nesmie pribudnúť chyba.
- Hodnoty: `@dataclass(frozen=True)` / `NamedTuple`; slovník z JSON → `TypedDict`; magické reťazce → `Enum` / `Literal`.
- Výnimky konkrétne, prebalenie `raise NovaChyba(...) from e`; zámerné ignorovanie `contextlib.suppress(X)`.
- Súbory, spojenia, zámky cez `with`; cesty `pathlib.Path`, `read_text(encoding="utf-8")`.
- Logovanie `logger = logging.getLogger(__name__)`, `logger.info("x=%s", x)`; v `except` `logger.exception(...)`.
- `print()` len ako výstup CLI; importy stdlib → tretie strany → lokálne, žiadne `import *`.
- Žiadne side effecty pri importe modulu (spojenia, čítanie env, registrácie) — patria do funkcie alebo továrne.

## Zakázané

- debug kód `breakpoint()`, `pdb.set_trace()` — hook ich hlási; dočasné `print()` hook nezachytí, zmaž ho sám
- holé `except:` a tiché `except Exception: pass` / `return None` pri chybe
- SQL skladané f-stringom, `%`, `+`, `.format()` → parametre (`cur.execute(sql, params)`, ORM, `text()` s väzbami)
- `subprocess` so `shell=True` nad premennými, `eval`/`exec`/`pickle`/`yaml.load` nad vstupom zvonku
- `verify=False` a HTTP volanie bez `timeout=`
- tajomstvá v kóde a v logu → env / `.env` (nie je v gite)

## DB a výkon

- N+1 (relácia načítaná v cykle) → Django `select_related`/`prefetch_related`, SQLAlchemy `selectinload`/`joinedload`; upozorni, oprav so súhlasom.
- Zmena modelu bez migrácie → opýtaj sa, či ju chce; commitnutú migráciu neupravuj, vytvor novú.
- Transakciu otvára volajúci (view, servis, úloha), nie pomocná funkcia hlboko v kóde.
- Formuláre a endpointy meniace stav: CSRF ochrana (Django middleware, Flask-WTF); šablóny s autoescape, `|safe` / `Markup()` len s dôvodom.

## Komentáre

- Krátke alebo žiadne; max 3–4 riadky nad funkciou, drž hustotu okolitého súboru.
- Len to, čo z kódu nevidno a čo bráni regresii; docstring na verejnom API, ak ho projekt používa.
- Žiadne merania, časy, produkčné dáta, história ani stopa po hľadaní riešenia. Sémantiku drží test.

## Pasce

- Meniteľný default `def f(x=[])` sa zdieľa medzi volaniami → `x: list[T] | None = None` a vytvorenie vo funkcii.
- `== None` / `type(x) ==` → `is None` / `isinstance`.
- `datetime.now()` je naivný → `datetime.now(timezone.utc)`; naivný a aware dátum sa nedajú porovnať.
- Blokujúce volanie v `async def` (`time.sleep`, `requests`, sync DB driver) zastaví celý event loop.
- `functools.cache` na metóde drží `self` naživo → únik pamäte.
- Peniaze vo `float` zaokrúhľujú → `Decimal`.
- Kruhový import → rozdeľ modul; `try/except ImportError` ho len skryje.
- Tieňovanie vstavaných mien (`list`, `id`, `type`, `input`) rozbije kód o pár riadkov nižšie.
- Systémový `python3` namiesto venv projektu → iná verzia a chýbajúce závislosti; príkazy podľa `.claude/devkit.json`.
