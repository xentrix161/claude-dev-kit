---
name: ecc-python-patterns
description: "Pythonovské idiómy: typové anotácie, výnimky, kontextové manažéry, dataclasses, generátory, súbežnosť, bezpečnosť a anti-vzory. Použi pri písaní, refaktore alebo review Python kódu."
paths:
  - "**/*.py"
---
<!-- prevzaté z ECC skills/python-patterns/SKILL.md @ b92f181, upravené -->

# Python — vzory a idiómy

- Prednosť má projekt: `CLAUDE.md`, `.claude/rules/*.md`, `pyproject.toml` (`requires-python`, ruff, mypy) a štýl okolitého kódu.
- Overenie: `/dev:check` (ruff + mypy + pytest podľa `.claude/devkit.json`); výsledok hlás z výstupu, nie odhadom.
- Nástroje z venv projektu (`.venv/bin/ruff`) alebo cez `docker exec -i -w <workdir> <kontajner>` podľa `devkit.json`, nie zo systémového Pythonu.

## Zásady

- Čitateľnosť pred dôvtipom: `[u for u in users if u.is_active]`, nie `[x for x in u if x.a]`.
- Explicitné pred implicitným: žiadne side effecty pri importe, konfigurácia ide parametrom.
- EAFP tam, kde je chýbajúca hodnota výnimočná (`try: d[k]` / `except KeyError`); bežný prípad `d.get(k, default)`.
- Funkcia robí jednu vec; > 5 parametrov → dataclass; vnorenie > 3 úrovne → early return.
- Magické čísla a reťazce → konštanta, `Enum` alebo `Literal`.

## Typové anotácie

```python
from typing import Final, Literal, Protocol, TypedDict

MAX_RETRIES: Final = 3
Status = Literal["draft", "sent", "paid"]

class UserRow(TypedDict):                  # tvar slovníka z JSON alebo DB
    id: int
    email: str

class UserRepository(Protocol):            # duck typing, mypy ho overí
    def find(self, user_id: int) -> UserRow | None: ...

def first[T](items: list[T]) -> T | None:  # 3.12+; staršie: T = TypeVar("T")
    return items[0] if items else None
```

- Vstavané generiká `list[str]`, `dict[str, int]` (3.9+); `X | None` od 3.10, inak `Optional[X]` alebo `from __future__ import annotations`.
- Verejné funkcie a metódy anotuj vrátane návratového typu; `Any` len na hranici (JSON, netypovaná knižnica).
- `Enum`, keď má hodnota správanie alebo ide do DB; `Literal` pre malú množinu reťazcov.
- `cast()` je tvrdenie bez kontroly → radšej zúženie cez `isinstance`.
- `# type: ignore[kód]` vždy s konkrétnym kódom, nikdy plošne.

## Výnimky

```python
class AppError(Exception): ...
class ConfigError(AppError): ...

def load_config(path: Path) -> Config:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as e:
        raise ConfigError(f"chýba konfigurácia: {path}") from e
    except json.JSONDecodeError as e:
        raise ConfigError(f"neplatný JSON: {path}") from e
    return Config.from_dict(data)
```

- Chytaj konkrétne výnimky; holé `except:` chytí aj `KeyboardInterrupt` a `SystemExit`.
- `raise … from e` zachová pôvodný traceback; `from None` len zámerne.
- Žiadne tiché zlyhanie (`except Exception: pass`, `return None` pri chybe) — zaloguj (`logger.exception`) a rozhodni: prebaliť, vrátiť volajúcemu, alebo nechať prebublať.
- Zámerné ignorovanie: `with contextlib.suppress(FileNotFoundError):`.
- Vlastná hierarchia výnimiek per balík; volajúci chytá základnú triedu.

## Kontextové manažéry

```python
@contextmanager
def transaction(conn: Connection) -> Iterator[Connection]:
    conn.begin()
    try:
        yield conn
    except Exception:
        conn.rollback()
        raise
    else:
        conn.commit()
```

- Súbory, spojenia, zámky, dočasné adresáre vždy cez `with`.
- Viac zdrojov naraz: `contextlib.ExitStack`.
- `__exit__` vracia `False` (výnimku nepotlačí), pokiaľ potlačenie nie je účel.

## Kolekcie a generátory

- Jednoduchá transformácia = comprehension; viac podmienok alebo vedľajšie efekty = obyčajný cyklus.
- Veľké dáta lenivo: generátor (`yield`), `sum(x * x for x in xs)` bez medzizoznamu.
- `enumerate`, `zip(a, b, strict=True)` (3.10+), `itertools.islice`/`batched` (3.12+), `collections.Counter`/`defaultdict`.
- Členstvo v cykle cez `set`/`dict`, nie `list`; reťazce v cykle cez `"".join(...)`, nie `+=`.

## Dátové triedy

```python
@dataclass(frozen=True, slots=True)        # slots od 3.10
class Money:
    amount: Decimal
    currency: str = "EUR"
    tags: list[str] = field(default_factory=list)

    def __post_init__(self) -> None:
        if self.amount < 0:
            raise ValueError(f"záporná suma: {self.amount}")
```

- Hodnotové objekty `frozen=True`; meniteľný default len cez `default_factory`.
- Vstup zvonku (API, súbor, formulár) validuj na hranici — pydantic/attrs, ak ich projekt používa; vnútri už čisté typy.
- Peniaze `Decimal`, nie `float`.

## Dekorátory

- Vždy `@functools.wraps(func)`; typ dekorátora cez `ParamSpec`: `def deco(func: Callable[P, R]) -> Callable[P, R]`.
- `functools.cache`/`lru_cache` na metóde drží `self` naživo (únik pamäte) → funkcia na úrovni modulu alebo `cached_property`.

## Súbežnosť

- I/O → `asyncio` alebo `ThreadPoolExecutor`; CPU → `ProcessPoolExecutor`.
- V `async def` nič blokujúce: `time.sleep` → `await asyncio.sleep`, `requests` → `httpx.AsyncClient`, sync driver → `asyncio.to_thread`.
- Skupina úloh: `asyncio.TaskGroup` (3.11+); `gather(..., return_exceptions=True)` vyžaduje prejsť výsledky a chyby ošetriť.
- Zdieľaný meniteľný stav medzi vláknami → `threading.Lock`, lepšie fronta bez zdieľania.
- Každé sieťové volanie s `timeout=`.

## Moduly a importy

- Poradie stdlib → tretie strany → lokálne (ruff `I`); absolútne importy v balíku.
- Žiadne `from x import *`; verejné API balíka cez `__all__`.
- Kruhový import → rozdeľ modul; `if TYPE_CHECKING:` len pre importy kvôli anotáciám.
- Spustiteľný modul: `def main() -> int` + `if __name__ == "__main__": raise SystemExit(main())`.
- Rozloženie `src/<balík>/` + `tests/`; konfigurácia nástrojov v `pyproject.toml`.

## Výkon

- Najprv meraj (`python -m cProfile -s cumtime`, `timeit`), potom optimalizuj.
- N+1 v ORM: Django `select_related`/`prefetch_related`, SQLAlchemy `selectinload`/`joinedload`; dotaz v cykle = podozrenie.
- `slots=True` / `__slots__` pri veľkom počte inštancií.

## Bezpečnosť

- SQL len s parametrami: `cur.execute("SELECT … WHERE id = %s", (uid,))`, SQLAlchemy `text("… :id")` + parametre; nikdy f-string, `%`, `+`, `.format()`.
- `subprocess.run(["git", "log", ref], check=True)` — zoznam argumentov, bez `shell=True`.
- `yaml.safe_load`; `pickle`, `eval`, `exec`, `marshal` nikdy nad vstupom zvonku; literály cez `ast.literal_eval`.
- Tajomstvá z env / `.env`, nie v kóde ani v logu; tokeny `secrets.token_urlsafe()`, heslá bcrypt/argon2, nie `hashlib`.
- Cesta od používateľa: `(base / name).resolve().is_relative_to(base)`.
- HTTP: `timeout=` vždy, `verify=False` nikdy.

## Anti-vzory → náhrada

| Zle | Dobre |
|---|---|
| `def f(items=[])` | `items: list[str] \| None = None` + `if items is None: items = []` |
| `type(o) == list` | `isinstance(o, list)` |
| `v == None` | `v is None` |
| `except:` / `except Exception: pass` | konkrétna výnimka + log alebo prebalenie |
| `from m import *` | explicitné mená |
| `print()` na ladenie, `breakpoint()` | `logging`; debug kód zmaž |
| `logger.info(f"x={x}")` | `logger.info("x=%s", x)` |
| `open(p).read()` bez `with` | `Path(p).read_text(encoding="utf-8")` |
| `datetime.now()` (naivný) | `datetime.now(timezone.utc)` |
| tieňovanie `list`, `id`, `type` | iné meno |

## Výstup pri review

- Nálezy `súbor:riadok — výstih`, najprv bezpečnosť a chyby, potom typy a idiómy; štýl rieši ruff, nehlásiť.
