---
name: review
description: "Code review zmien (necommitnuté, vetva, cesta): bugy, bezpečnosť, súlad s docs/plans, zastarané CLAUDE.md a rules; --security pridá hĺbkový bezpečnostný audit. Nálezy 🔴🟡🔵 so súbor:riadok."
argument-hint: "[branch [base]] [--security] [cesta…]"
disable-model-invocation: true
---
<!-- filter istoty a checklisty čiastočne prevzaté z ECC agents/code-reviewer.md + skills/security-review @ b92f181, upravené -->

# Code review

Rýchly review zmien. Výstup je celý zoznam nálezov v predpísanom riadkovom formáte, bez vaty, po slovensky. Argumenty: `$ARGUMENTS`

## Rozsah (podľa argumentov)

- **bez argumentu** → necommitnuté zmeny: `git diff` + `git diff --staged` + `git status` (aj nesledované súbory)
- **`branch [base]`** (doslova slovo `branch`) → celá vetva oproti base: `git diff <base>...HEAD`
  - `base` = zadaný argument; inak `master`, ak existuje (`git rev-parse --verify master`), inak `main`
- **cesta** (súbor/adresár) → celý obsah týchto súborov, nie diff
- **`--security`** → kombinuje sa s rozsahom vyššie a pridá hĺbkový bezpečnostný prechod (nižšie)
  - bez zmien a bez cesty sa opýtaj: „Audit celého projektu alebo konkrétnych súborov? (cesta, alebo Enter = celý projekt)"
- Žiadne zmeny → oznám jednou vetou a skonči.

## Príprava

1. **Stack**: `.claude/devkit.json` → `stack`; inak `composer.json` (`nette/application` → Nette, `symfony/framework-bundle` → Symfony), `pyproject.toml` / `requirements*.txt` → Python.
2. **`REVIEW.md`** (koreň repa, inak `.claude/REVIEW.md`): ak existuje, má prednosť — čo je Important a čo Nit, max 5 nitov, zoznam „nehlásiť", projektové kontroly a pasce.
3. **Plán úlohy**: číslo z vetvy (`git branch --show-current`) alebo z `[#XX]` v commitoch rozsahu → `docs/plans/<číslo>-*.md` (aj `#<číslo>-*.md`), plus plán zmenený priamo v diffe. Žiadny → prechod 3 vynechaj potichu.
4. **Kontext**: pri každom kandidátovi čítaj celú metódu/súbor, volajúcich (Grep) a testy — nie len hunk diffu.

## Veľký diff — delegácia

Pri > ~400 zmenených riadkoch alebo > 15 súboroch (`git diff --shortstat`) spusti v jednej správe paralelne read-only agentov:
- `dev:ecc-silent-failure-hunter` — prehltnuté výnimky, `@`, prázdne `catch`, tiché fallbacky
- `dev:ecc-performance-optimizer` — N+1, dotazy v cykle, chýbajúce indexy a LIMIT

Daj im presný rozsah (príkaz diffu, zoznam súborov, stack, kontajner z `devkit.json`). Ich nálezy sú len kandidáti: každý over sám podľa pravidiel nižšie, zlúč s vlastnými a prečísluj.

## Prechody

Pri diffe hodnoť zmenený kód; nezmenený len pri CRITICAL bezpečnostnom probléme. Pri ceste celý obsah.

### 1. Bugy & logika
- off-by-one, zlé podmienky, edge cases, null (Dibi 5 `fetch()` vracia `null`, nie `false`), copy-paste chyby
- typy: `instanceof \DateTime` pri `DateTimeImmutable` z DB vrstvy → `\DateTimeInterface`; chýbajúce typy parametrov a návratov; `strict_types` tam, kde ho projekt používa
- error handling: prázdny `catch`, `@` operátor, tichý fallback; `begin()/commit()` v modeli (MySQL `BEGIN` commitne otvorenú transakciu)
- performance: N+1, dotazy v cykle, veľký výsledok bez LIMIT/stránkovania, nový filter bez indexu — opravu navrhni, nevnucuj
- debug kód (`dump`, `dd`, `bdump`, `var_dump`, `print_r`, `console.log`), `die()`/`exit()`, mŕtvy kód
- zmena entity/schémy bez migrácie → 🟡 „chýba migrácia — chceš ju?"
- nová cesta v logike bez testu; oprava bugu bez regresného testu
- komentáre: história zmien, merania, počty riadkov → 🔵; zmienka o produkčnej DB alebo reálnych dátach → 🟡

### 2. Security
- SQL: hodnota skladaná do SQL/DQL reťazcom namiesto parametra
- XSS: Latte `|noescape` (Latte 2 `{!$var}`), Twig `|raw` bez jasného dôvodu; JS `innerHTML` / `.html()` s dátami
- AuthZ: nová akcia/route bez kontroly oprávnenia; objekt podľa ID z requestu bez overenia vlastníctva (IDOR)
- mass assignment: celý vstup z formulára/requestu rovno do `update()` alebo entity; insecure deserializácia (`unserialize`, `pickle`, `yaml.load` na vstupe)
- CSRF: formulár meniaci stav bez ochrany; zmena stavu cez GET
- tajomstvá v kóde, logoch alebo commitnutom configu; osobné údaje v logoch a chybových hláškach
- súbory: upload bez obmedzenia typu/veľkosti, cesta zo vstupu (path traversal), dočasné súbory, ktoré ostávajú ležať

### 3. Súlad s plánom (`docs/plans/*.md`)
- zmenené súbory mimo sekcie „Súbory" (okrem testov a docs) → jeden zlúčený nález
- diff robí niečo zo sekcie „Mimo rozsahu"
- „Dôkaz" sľubuje test alebo výstup, ktorý v zmene chýba
- odchýlka od plánu bez úpravy plánu v tej istej zmene
- odkaz na nález: `docs/plans/<súbor>.md:<riadok>`

### 4. Zastarané CLAUDE.md a rules
- grep `CLAUDE.md` (aj vnorené) a `.claude/rules/*.md` na to, čo diff mení alebo maže: súbory, triedy, metódy, config kľúče, make targety, príkazy, kontajnery, testsuites
- pravidlo v docs, ktoré zmena porušuje alebo ruší
- čísla (počty testov, časy) hlás len keď ich diff zjavne mení; navrhni namiesto čísla príklad zdravého výstupu
- nefunkčný príkaz alebo cesta → 🟡; chýbajúca zmienka o novej dôležitej veci → 🔵

### Checklist podľa stacku

**Nette / Latte / Dibi**
- presenter: nová `action*` / `handle*` bez kontroly oprávnenia (`$this->getUser()->isAllowed()`, `startup()` base presentera); stav meniaci kód v `action*` / `render*` cez GET
- formuláre: `addProtection()` na formulároch meniacich stav; validácia na serveri, nie len v JS; `getValues()` rovno do `update()` (mass assignment)
- Dibi / Nette Database: parametre (`?`, `%s`, `%i`, `%in`), nie reťazec; identifikátory a `ORDER BY` zo vstupu len cez whitelist
- Latte: `|noescape` (v Latte 2 aj `{!$x}`) len s dôvodom; v Latte 3 je `{!$x}` výpis negácie — vždy chyba; odkazy cez `n:href` / `{link}`; dáta do JS cez `data-*` atribút s `{$x}`
- markup, na ktorý sa viaže JS (triedy, `data-*`, `.closest()` / `.next()` traverz) — zmena rozloženia rozbije JS ticho
- `die()` / `exit()` → `throw` alebo `$this->terminate()`; služba chýba v neon configu
- Phinx: úprava už commitnutej migrácie (vytvor novú); zmena schémy bez migrácie

**Symfony / Twig / Doctrine**
- controller/route bez `#[IsGranted]`, `denyAccessUnlessGranted()` alebo votera; API Platform operácia bez `security:`
- CSRF: `csrf_protection: false`; zmena stavu cez GET route
- Twig `|raw`, `{% autoescape false %}`; v JS kontexte `|e('js')`
- Doctrine: DQL/QueryBuilder reťazcom → `setParameter()`; lazy loading v cykle (N+1) → `addSelect` + join; `flush()` v cykle; zmena mappingu bez migrácie; nový filter bez `#[ORM\Index]`
- validácia `#[Assert\…]` na DTO/entite; serializer skupiny neodhaľujú citlivé polia
- `APP_DEBUG` / `dev` v produkčnom configu; tajomstvá v commitnutom `.env` namiesto `.env.local` alebo secrets

**Python**
- SQL cez f-string, `%` alebo `.format()` → parametre DB API / ORM
- `subprocess(..., shell=True)` so vstupom; `eval` / `exec`; `pickle` / `yaml.load` na nedôveryhodných dátach
- mutable default argument; holé `except:` alebo `except Exception: pass`; `assert` ako validácia vstupu
- `requests` bez `timeout`; súbor bez `with`; naivný vs. aware `datetime`
- Django/FastAPI: `csrf_exempt`, `mark_safe` / `|safe`, endpoint bez permission dependency
- projekt s mypy: nová verejná funkcia bez anotácií

## `--security` — hĺbkový prechod

Navyše k prechodu 2. Pri celom projekte začni vstupnými bodmi: presentery/controllery, formuláre, API, CLI, DB dotazy, auth, config.
- **Tajomstvá**: heslá, kľúče, tokeny v kóde a configu; `config.local.*`, `.env*`, `.test-credentials` v gite; tajomstvo v URL alebo logu
- **Injection**: SQL/DQL vrátane identifikátorov; príkazy (`exec`, `shell_exec`, `system`, `proc_open`, `subprocess`) bez `escapeshellarg` / zoznamu argumentov; XXE (`LIBXML_NOENT`, `LIBXML_DTDLOAD` pri XML zo vstupu); `unserialize` / `pickle` / `yaml.load` na vstupe
- **XSS**: každý neescapovaný výstup (Latte, Twig, JS), JSON vložený do šablóny
- **AuthN**: heslá cez `password_hash` / `password_verify` (nie SHA1, MD5); tokeny z `random_bytes` / `secrets` (nie `rand`, `uniqid`); porovnanie tokenu `hash_equals`; rate limit na login
- **AuthZ**: každý vstupný bod má kontrolu; IDOR; zakomentované ACL
- **CSRF**: formuláre, signály, zmena stavu cez GET
- **Súbory**: upload (typ, veľkosť, prípona, úložisko mimo webrootu), path traversal, dočasné súbory s osobnými údajmi
- **Konfigurácia**: debug režim/Tracy v produkcii, stack trace navonok, CORS `*`, chýbajúce hlavičky (CSP, X-Frame-Options)
- **Závislosti**: `composer audit` (s kontajnerom z `devkit.json`: `docker exec -i -w <workdir> <container> sh -c 'composer audit'`, workdir = `appRoot`, vo worktree `appRoot/<cesta worktree>`; bez kontajnera na hostiteľovi), pri Pythone `pip-audit`, ak je dostupný; hlás len balíky so známou zraniteľnosťou
- závažnosť: CRITICAL (zneužiteľné) → 🔴 · HIGH (opraviť pred nasadením) a MEDIUM (oslabuje ochranu) → 🟡 · LOW (hardening) → 🔵

## Overenie (povinné pred nahlásením)

Každého kandidáta over priamo v kóde — prečítaj kontext okolo riadku. Ak sa nepotvrdí, zahoď. Nefabrikuj problémy.
- hlás len pri istote > 80 %
- 4 otázky: viem presný riadok? viem konkrétny scenár zlyhania (vstup → stav → zlý výsledok)? čítal som kontext (volajúci, typy, testy)? je závažnosť obhájiteľná? Ktorékoľvek „nie" → zníž závažnosť alebo zahoď.
- 🔴 len s dôkazom: scenár zlyhania + prečo ho nezachytí existujúca ochrana (typ, validácia, framework). Inak 🟡 alebo zahoď.
- podobné nálezy zlúč do jedného riadku („3 akcie bez `isAllowed()`" pri prvom výskyte, ostatné v detaile)
- nula nálezov je platný výsledok

Nehlás (časté falošné poplachy):
- „chýba error handling", keď chybu rieši volajúci alebo framework (error presenter, Tracy, kernel listener)
- „chýba validácia" pri internej funkcii, ktorej volajúci už validuje — vystopuj aspoň jedného volajúceho
- „možný null", keď ho v scope ošetruje guard alebo typ
- N+1 pri cykle s pevnou malou kardinalitou; „magic number" pri HTTP kódoch a zjavných konštantách
- „dlhá funkcia" pri `switch`, configu, testovacích tabuľkách; natvrdo zadané hodnoty v testoch a fixtures
- štýl, ktorý stráži phpcs / PHPStan / ruff alebo hooky kitu; všetko zo zoznamu „nehlásiť" v `REVIEW.md`

## Výstup — zoznam nálezov (bez balastu)

- Jeden riadok na nález: `<emoji> N. <súbor>:<riadok> — <výstih do ~10 slov>`
  - 🔴 = CRITICAL, 🟡 = WARNING, 🔵 = SUGGESTION
  - nálezy čísluj (1, 2, 3…), nech sa dá dopýtať detail
  - poradie 🔴 → 🟡 → 🔵, v rámci závažnosti bezpečnosť prvá
- S `REVIEW.md`: Important = 🔴/🟡, Nit = 🔵, najviac 5 nitov (vyber najužitočnejšie)
- SUGGESTION patria do toho istého zoznamu v chate ako ostatné nálezy
- Do `.md` súboru suggestions zapisuj LEN keď o to výslovne požiadam — vtedy appendni vybrané do `.review-notes.md` v roote projektu (s dátumom), nech sa k nim viem vrátiť. Súbor NEcommitujeme: ak nie je ignorovaný gitom (`git check-ignore -q .review-notes.md`), pridaj ho do `.git/info/exclude`
- Na konci jeden súhrnný riadok: `X critical, Y warning, Z suggestions`
- Ak nič vážne: `Čisté, nič kritické.` a koniec
- ŽIADNE dlhé vysvetlenia, bloky kódu ani odseky. Detail dodaj len keď si ho vyžiadam (napr. „detail 3") — vtedy scenár zlyhania, dôkaz a návrh opravy; pri bezpečnostnom náleze aj ako sa dá zneužiť a opravu s ukážkou kódu

Príklad výstupu:
```text
🔴 1. app/models/UserModel.php:42 — ID z requestu skladané do SQL reťazcom
🟡 2. app/presenters/BatchPresenter.php:118 — delete akcia bez isAllowed()
🟡 3. CLAUDE.md:57 — zastarané: target test-unit už neexistuje
🔵 4. libs/Export.php:10 — komentár opisuje históriu zmeny
1 critical, 2 warning, 1 suggestions
```

## Pravidlá

- Len reálne problémy, nie štýlové preferencie
- Opravu ponúkni až keď o ňu požiadam; po oprave odporuč `/dev:check`
- Komunikuj po slovensky
