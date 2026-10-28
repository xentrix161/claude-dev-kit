---
paths:
  - "**/*.latte"
  - "www/css/**"
  - "www/js/**"
  - "assets/**"
---

# Latte a frontend

## Escapovanie

- Latte escapuje podľa kontextu (HTML, atribút, `<script>`, URL) — nechaj ho; v `<script>` nedávaj okolo `{$var}` úvodzovky, Latte vypíše JS literál.
- Bez escapovania len `{$var|noescape}`, len pre HTML prečistené na serveri (napr. HTMLPurifier) a s komentárom prečo.
- URL len cez `n:href`, `{link}`, `{plink}`, nie skladaním reťazca.

## Bootstrap a skripty

- Bootstrap 5 používa `data-bs-*` (`data-bs-toggle`, `data-bs-target`); BS4 zápis `data-toggle` ticho nefunguje. Verziu over v layoute.
- Nenačítavaj dve verzie Bootstrapu ani jQuery naraz — pluginy sa bijú.
- Poradie `<script>` v layoute nemeň (`defer`, presun na koniec `body`) bez overenia — inicializácie závisia od poradia.

## JS kotvy

- Triedy, `id` a `data-*`, na ktorých visí JS, sú kontrakt: pred premenovaním či odstránením `grep` v `www/js/` a šablónach.
- Pri zmene rozloženia cieľ na sémantickú triedu (`.closest('.js-row')`), nie na pozíciu (`.next()`, `.parent()`).
- Kotvy, ktoré CLAUDE.md alebo komentár v šablóne označuje ako kritické, ostávajú bez výnimky.

## CSS a vendor

- Vendor knižnice (`vendor/`, vendorizované súbory vo `www/`) sa needitujú — ostávajú čisté pre upgrade.
- Override vendor knižnice patrí do vlastného súboru načítaného až po nej; inak by potreboval `!important`.
- Farby a rozmery cez existujúce tokeny a premenné projektu; nová hex hodnota len keď token chýba.
- Bloky a `id`, ktoré layout a skripty očakávajú (zoznam v CLAUDE.md), musia ostať.

## Prístupnosť

- Každé pole má `<label for>`, obrázok `alt`, akcia je `<button>`, nie `<a href="#">`.
- Stav nevyjadruj len farbou; ikona bez textu má `aria-label`.

## Overenie v prehliadači

- Prehliadač drží CSS v cache a `location.reload(true)` ju neobíde → `fetch(href, {cache: 'reload'})` pre zmenené `<link>`, potom `location.reload()`.
- Po prepnutí vetvy vyčisti `temp/cache` (skompilované šablóny).

## Pasce

- Latte 3: `{!$var}` vypíše negáciu výrazu (prázdno alebo `1`), nie HTML — chyba bez hlášky.
- `{block}` v šablóne, ktorý layout nevkladá, sa ticho nevykreslí → over názov bloku v `@layout.latte`.
- jQuery na prázdnej kolekcii nehádže → rozbitá kotva = formulár ticho nefunguje, konzola čistá, HTTP 200.
- `n:if` na elemente, ktorý hľadá JS, ho pre inú rolu odstráni — chyba sa ukáže len tej role.
- Hromadná náhrada `data-*` ↔ `data-bs-*` bez overenia verzie Bootstrapu rozbije všetky modály a dropdowny naraz.
- `|noescape` v atribúte alebo v `<script>` je XSS aj pri „dôveryhodných" dátach z DB.
