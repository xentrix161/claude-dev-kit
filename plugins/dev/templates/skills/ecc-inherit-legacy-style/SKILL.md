---
name: ecc-inherit-legacy-style
description: Drž konvencie legacy projektu namiesto modernizácie — zisti nepísané pravidlá z kódu (vzorové súbory, pomenovanie, chyby), konflikty rieš s používateľom po jednom a zapíš ich do .claude/rules/. Pri práci v ručne písanom legacy kóde.
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash(git ls-files *)
  - Bash(git grep *)
  - Bash(git log *)
  - Bash(git diff *)
---
<!-- prevzaté z ECC skills/inherit-legacy-style/SKILL.md @ b92f181, upravené -->

# Zdediť štýl legacy projektu

Cieľ: nový kód vyzerá ako zvyšok projektu. Skill nehodnotí kvalitu ani technológiu — len bráni driftu
(moderný štýl vmiešaný do starého kódu).

## Kedy

- prvá práca v ručne písanom legacy projekte (staré PHP, bez typov, vlastné vzory)
- používateľ nechce, aby nový kód „vyzeral inak" než zvyšok
- po väčšej zmene v projekte (nový modul, nový člen tímu) — aktualizácia pravidiel
- `/dev:project-init` ponúkol vrstvu B a projekt je legacy

## Krok 0 — režim (oznám jednou vetou, nepýtaj sa)

- `.claude/rules/conventions.md` neexistuje alebo nemá hlavičku `legacy-style` → **A: plný sken**
- existuje s hlavičkou → **B: prírastkový sken**
- súbor zdieľaš s `/dev:project-init` (krok infer-conventions) — jeho riadky neprepisuj ani neduplikuj,
  doplň hlavičku a sekcie

## A — Plný sken

1. **Rozsah** — vlastný kód bez knižníc:
   `git ls-files -- . ':!*vendor*' ':!*node_modules*' ':!*.min.*' | grep -cE '\.(php|phtml|latte|twig|neon|ya?ml|py|js|ts|css|scss)$'`;
   knižnice skopírované do `www/` (jQuery, pluginy) odpočítaj a neskenuj — nie sú štýl projektu

   | Úroveň | Súbory | Stratégia |
   |---|---|---|
   | malý | ≲ 50 | prečítaj všetko |
   | stredný | 50–500 | infra vrstva celá, biznis vrstva 2–3 vzorky na dimenziu |
   | veľký | ≳ 500 | najprv štatistiky (`git grep -c`, `git log --stat`), potom cielené čítanie |

2. **Čo sa smie písať** — verzia jazyka z `composer.json` (`require.php`, `config.platform.php`) alebo
   `pyproject.toml` a z behového prostredia (kontajner z `.claude/devkit.json`); čo vynucuje phpcs,
   PHPStan, rector, ruff → nezapisuj, stráži to nástroj
3. **Sken v 4 dimenziách**, každý nález s dôkazom `súbor:riadok` a počtom výskytov:
   1. *Anatómia súboru* — poradie (namespace/use → konštanty → vlastnosti → konštruktor → verejné →
      privátne), `declare(strict_types=1)` áno/nie, taby vs. medzery, jazyk komentárov a hlášok
   2. *Stav a tok* — pomenovanie (camelCase/snake_case, `get/find/load`), návrat pri „nenájdené"
      (`null`/`false`/výnimka), príznaky, stránkovanie, práca s formulármi
   3. *Infraštruktúra* — kde žijú zdieľané veci (base presenter/kontrolér, modely/repozitáre, helpery,
      DI služby), prístup k DB (query builder / raw SQL / ORM), registrácia služieb
   4. *Chyby* — výnimky vs. návratové kódy, kde sa chytajú, logovanie, hlásenia používateľovi (flash)

   Počítanie, napr.: `git grep -l 'declare(strict_types' -- '*.php' | wc -l` vs. `git ls-files '*.php' | wc -l`
4. **Filter šumu**
   - slabý signál (menšina < 5 % a < 10 výskytov) → väčšina vyhráva, menšina ide do NEROBIŤ bez otázky
   - silný signál (rozdelenie blízko pol na pol alebo sémantický rozdiel v jadre) → otázka
   - malý projekt (≲ 50 súborov): „3 vs. 2" nie je väčšina → otázka
   - novšie súbory (`git log --diff-filter=A --format= --name-only | head -50`) môžu byť zámerný vývoj
     → spomeň to v otázke
5. **Otázky po jednej** (nikdy viac naraz; `AskUserQuestion`, ak je k dispozícii), čakaj na odpoveď:
   > Dôkaz: `app/A.php:12` robí X (14×), `app/B.php:40` robí Y (11×)
   > Riziko: miešanie oboch rozbije jednotný štýl
   > `1` drž X · `2` drž Y · `3` je to vývoj, platí nové · `4` iné pravidlo
6. **Návrh pravidiel** — ukáž celý text (formát nižšie), zapíš až po súhlase
7. **Vynútenie** — jedna otázka:
   - `1` pravidlá v `.claude/rules/conventions.md` (odporúčané) — načítajú sa samy, CLAUDE.md netreba meniť
   - `2` pravidlá + mechanické `guards` v `.claude/devkit.json` (len ak ho projekt má) pre NEROBIŤ, ktoré
     chytí regex (POSIX ERE, kontrolujú sa len pridané riadky), napr.
     `{"id": "legacy-strict-types", "ext": [".php"], "pattern": "declare\\(strict_types", "message": "projekt nepoužíva strict_types"}`
   - `3` len dokument `docs/conventions.md` (nenačíta sa automaticky)

## Formát `.claude/rules/conventions.md`

```markdown
---
paths:
  - "**/*.php"
  - "**/*.latte"
---
<!-- legacy-style: <git sha> · <úroveň> · <YYYY-MM-DD> -->
# Konvencie projektu

Pred písaním kódu si vyber vzorový súbor z rovnakej vrstvy a drž jeho tvar. Nemodernizuj.

## Vzorové súbory
- `app/Presenters/OrderPresenter.php` — presenter: poradie metód, flash správy, redirect po POST

## Pomenovanie a tok
- metódy modelu `find*` vracajú `null`, nie `false` (`app/Model/UserModel.php:42`)

## NEROBIŤ
- `declare(strict_types=1)` v nových súboroch — projekt ho nepoužíva (0 z 180 súborov)

## Vývoj pravidiel
### YYYY-MM-DD
- …
```

- celý súbor ≤ 60 riadkov; každé pravidlo kontrolovateľné a s dôkazom
- `paths:` podľa jazykov projektu, nech sa pravidlá nenačítavajú pri nesúvisiacich súboroch
- súbor už existuje (z `/dev:project-init`) → `paths:` len rozšír o globy nových pravidiel, hlavičku
  `legacy-style` vlož hneď za frontmatter, existujúce riadky nechaj

## B — Prírastkový sken

1. prečítaj pravidlá, zober sha z hlavičky → `git diff --stat <sha> HEAD`
2. veľký rozdiel (stovky súborov) → len `--stat` + vzorky najväčších zmien
3. porovnaj nový kód s pravidlami; konflikty → otázky po jednej (krok A5)
4. doplň záznam do „Vývoj pravidiel"; staré pravidlo neprepisuj, označ ho `(nahradené YYYY-MM-DD)`
5. aktualizuj sha a dátum v hlavičke

## Legacy PHP — typický drift (bez súhlasu nerob)

- syntax novšia než PHP projektu: 7.4 nemá `match`, union typy, promovaný konštruktor, `?->`,
  pomenované argumenty (8.0); `enum`, `readonly`, `never` (8.1)
- `declare(strict_types=1)`, typy vlastností/parametrov/návratov, `final` do súborov, ktoré ich nemajú —
  `strict_types` mení správanie volaní (koercia skalárov)
- prepis `array()` → `[]`, úvodzoviek a odsadenia v riadkoch, ktoré nemeníš → šum v diffe; ak to projekt
  vyžaduje (CLAUDE.md), len v menených riadkoch
- nová knižnica alebo vzor (DTO, repository, eventy, iný DI štýl) tam, kde projekt rieši vec inak
- iný prístup k DB než susedný kód (ORM vedľa query buildera, builder vedľa raw SQL)
- iný jazyk komentárov a hlášok než zvyšok súboru
- šablóny: nové bloky/makrá, ktoré layout nepoužíva; zmena štruktúry, na ktorú sa viaže JavaScript

## Čo sa nededí

- bezpečnostné chyby vzorových súborov: SQL skladané reťazcom, chýbajúce escapovanie, potlačenie chýb `@`,
  chýbajúca CSRF/ACL kontrola — štruktúru prevezmi, chybu nahlás jednou odrážkou
- debug výpisy a mŕtvy kód

## Anti-vzory skillu

- nepreskakuj meranie rozsahu — malý projekt podvzorkovaný, veľký čítaný celý = vyhodený kontext
- nikdy viac otázok naraz
- v režime B neprepisuj staré pravidlá
- nehodnoť kvalitu technológie, len zlaď štýl
- `guards` ani pravidlá nezapisuj bez súhlasu

## Výstup

- režim a úroveň jednou vetou
- návrh pravidiel: celý text v tvare z „Formát .claude/rules/conventions.md“, každé pravidlo s dôkazom `súbor:riadok`
- otázky po jednej
- na konci: čo sa zapísalo kam a ako to vrátiť
