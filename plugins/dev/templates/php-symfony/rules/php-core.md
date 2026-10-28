---
paths:
  - "**/*.php"
---

# PHP — jadro

- Typy všade: parametre, návratové hodnoty, vlastnosti; `mixed` len keď inak nejde.
- Závislosti cez constructor promotion s `readonly`; množiny hodnôt ako `enum`, nie konštanty.
- Striktné porovnania `===`/`!==`; `in_array($x, $list, true)`, `array_search(…, true)`.
- `match` namiesto reťaze `switch`/`if` pri mapovaní hodnôt; `match` bez zhody hodí výnimku — to je správne.
- `declare(strict_types=1);` drž podľa okolia: kde ho súbory majú, má ho aj nový súbor.
- Štýl podľa nástroja projektu (php-cs-fixer / phpcs, PSR-12) — neformátuj riadky mimo svojej zmeny.
- Chyba = výnimka, nie `false`/`null` ako signál; žiadny prázdny `catch`, zachyť len to, čo vieš ošetriť.
- V commitnutom kóde nie: `dump()`, `dd()`, `var_dump()`, `print_r()`, `die()`/`exit()`, operátor `@` (hook ich hlási v pridaných riadkoch).
- Dátumy ako `\DateTimeImmutable`; typové kontroly cez `\DateTimeInterface`.
- Komentáre krátke alebo žiadne: len čo z kódu nevidno a bráni regresii; bez histórie, meraní a odkazov na reálne dáta; sémantiku drží test.
- PHPStan: nový nález oprav v kóde; baseline sa nedopĺňa; `@phpstan-ignore` len s identifikátorom a dôvodom.

## Overenie

- Po každom edite beží `php -l` (hook); PHPStan nad zmenenými súbormi pri Stop, celý projekt `/dev:check`.
- `php vendor/bin/phpstan analyse -c <config>` → `[OK] No errors`.

## Pasce

- `instanceof \DateTime` ticho zlyhá na `\DateTimeImmutable` (knižnice ho vracajú čoraz častejšie) → kontroluj `\DateTimeInterface`.
- `!==` medzi hodnotami z rôznych zdrojov (API string vs. `bool`/`int` z DB) hlási rozdiel vždy → najprv normalizuj typ na oboch stranách.
- `empty('0')` je `true` — pri vstupoch z formulára/API rozlišuj `null`, `''` a `'0'`.
- `array_merge` prečísluje číselné kľúče; kľúče zachová `+` alebo `array_replace`.
- `json_decode` bez `JSON_THROW_ON_ERROR` vráti pri chybe ticho `null`.
- Peniaze nikdy ako `float` — `int` (centy) alebo `string`; kódy s úvodnými nulami ako `string`, nie `int`.
- phpstan-symfony s `containerXmlPath` potrebuje zohriatu cache (`var/cache/dev/*.xml`) → na čerstvom klone, v CI a vo worktree najprv `cache:warmup`.
- `phpstan.dist.neon` a baseline patria do gitu; lokálny `phpstan.neon` (ignorovaný) ich prebije a zmení výsledok.
