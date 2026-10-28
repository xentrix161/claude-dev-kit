---
name: ecc-design-system
description: Dizajn tokeny v server-renderovanom CSS — extrakcia farieb, písma a odsadení do CSS premenných, audit vizuálnej konzistencie (10 oblastí), generické AI vzory. Pri zakladaní tokenov, redizajne a review štýlov či šablón.
paths:
  - "www/css/**"
  - "assets/**/*.css"
  - "assets/**/*.scss"
  - "**/*.latte"
  - "**/*.twig"
---
<!-- prevzaté z ECC skills/design-system/SKILL.md @ b92f181, upravené -->

# Dizajn systém — tokeny a vizuálna konzistencia

Cieľ: každá farba, veľkosť a odsadenie pochádza z tokenov projektu. Nový prvok sa skladá z existujúcich
komponentov, nie z nových „takmer rovnakých" hodnôt.

## Kedy

- pridávaš alebo meníš farbu, písmo, odsadenie, zaoblenie, tieň v CSS alebo v šablóne
- audit konzistencie pred redizajnom alebo pri review štýlov
- projekt ešte nemá tokeny a treba ich založiť
- UI „nesedí" a nevieš prečo

## Tokeny projektu

- hodnoty projektu nepíš do tohto skillu (kópia šablóny ostáva čistá pre `/dev:project-init --sync`)
- hľadaj ich v `.claude/rules/projekt-frontend.md`, inak v `CLAUDE.md` (sekcia o štýloch)
- chýbajú → zisti ich z kódu (režim 1) a navrhni sekciu `## Dizajn tokeny` do
  `.claude/rules/projekt-frontend.md` (`paths:` na CSS a šablóny → načíta sa pri každej úprave štýlov);
  zapíš až po súhlase, v tomto tvare:

| Oblasť | Token / hodnota | Zdroj pravdy (súbor) |
|---|---|---|
| Značka (primárna, sekundárna) | _doplň_ | _doplň_ |
| Stavy (success, warning, danger, info) | _doplň_ | _doplň_ |
| Neutrálne (text, pozadie, okraje) | _doplň_ | _doplň_ |
| Písmo (rodina, škála veľkostí) | _doplň_ | _doplň_ |
| Škála odsadení | _doplň_ | _doplň_ |
| Zaoblenie, tiene | _doplň_ | _doplň_ |
| Breakpointy | _doplň_ | _doplň_ |
| CSS framework + verzia, sada ikon | _doplň_ | _doplň_ |
| Poradie načítania CSS | _doplň_ | layout šablóna |
| Vzorová stránka / styleguide | _doplň_ | _doplň_ |

## Pravidlá

- nová hodnota v CSS = token (`var(--…)`), nie natvrdo hex/px; výnimka len pre naozaj jednorazovú hodnotu
  a v odpovedi jedna odrážka prečo
- token chýba → navrhni ho (meno · hodnota · súbor), nepridávaj potichu odtieň blízky existujúcemu
- pomenovanie podľa účelu (`--color-danger`, `--space-3`), nie podľa vzhľadu (`--red-2`)
- jedna škála odsadení (napr. 4/8/16/24/32 px) a jedna typografická škála; mimo škály len s dôvodom
- pred zmenou tokenu zisti dopad: `git grep -n -- '--nazov-tokenu'` — zmena tokenu mení všetky miesta
- inline `style=""` v šablóne len pre dynamickú hodnotu z dát, inak trieda
- ak má projekt styleguide/vzorovú stránku, nový prvok sa drží jej vzorov

## Pasce

- **dva zdroje pravdy**: framework drží premennú (napr. `--bs-primary`), ale téma farbí selektory natvrdo
  → zmena len tokenu dá polovičný efekt; over, kde všade farba žije, a povedz to
- **poradie CSS**: override knižnice patrí do súboru načítaného **za** ňou; potreba `!important` = zlé poradie
- **vendor súbory** (framework, téma, knižnice v `vendor/`, `node_modules/` alebo skopírované do `www/`)
  needituj — override vo vlastnom súbore, nech ostanú čisté pre upgrade
- **verzia frameworku**: pred hromadnou zmenou atribútov/tried ju over z načítaného súboru, nie z pamäti
  (Bootstrap 4 `data-toggle` vs. 5 `data-bs-toggle`)
- **JS kotvy**: neodstraňuj triedy/atribúty, na ktoré sa viaže JavaScript (`git grep -n 'nazov-triedy'`
  v `*.js` aj šablónach); jQuery na prázdnej kolekcii nehádže → formulár zlyhá ticho
- **DOM traverzy** (`.closest()`, `.next()`, `.parent()`) sa rozbijú pri zmene rozloženia — cieľ na
  sémantickú triedu, nie na pozíciu súrodenca
- **poradie `<script>`** v layoute nemeň (`defer`, presun na koniec `body`) bez overenia — mení poradie
  vykonania a môže zdvojiť handlery

## Režim 1 — Extrakcia tokenov

1. Súbory: `git ls-files '*.css' '*.scss' '*.latte' '*.twig' ':!*vendor*'` (vendor cesty doplň podľa projektu)
2. Najčastejšie farby:
   `git grep -hoE '#[0-9a-fA-F]{3,8}' -- '*.css' '*.scss' ':!*vendor*' | tr 'A-F' 'a-f' | sort | uniq -c | sort -rn | head -30`
3. Rovnako `font-size`, `margin|padding|gap`, `border-radius`, `box-shadow`, `@media` breakpointy
4. Zoskup takmer rovnaké hodnoty (napr. `#1f6feb` vs. `#2070ea`, `15px` vs. `16px`) → kandidáti na zlúčenie
5. Návrh: CSS custom properties na `:root` v jednom súbore (napr. `variables.css`, `_tokens.css`),
   pomenované podľa účelu, + zoznam miest na nahradenie `súbor:riadok`
6. Zapisuj až po súhlase; `docs/design.md` s odôvodnením a HTML náhľad tokenov len na požiadanie

## Režim 2 — Audit (10 oblastí, skóre 0–10)

1. Farby — paleta projektu, alebo náhodné hex?
2. Typografia — jasná hierarchia h1 > h2 > h3 > text > popisok?
3. Odsadenia — škála, alebo ľubovoľné px?
4. Komponenty — rovnaké prvky vyzerajú rovnako (tlačidlá, tabuľky, formuláre, hlášky)?
5. Responzivita — zlomy pri breakpointoch, horizontálny scroll širokých tabuliek?
6. Tmavý režim — len ak ho projekt má, inak preskoč
7. Animácie — účelné, rešpektujú `prefers-reduced-motion`?
8. Prístupnosť — kontrast, viditeľný focus, veľkosť cieľov (detail: skill `dev:ecc-accessibility`)
9. Hustota informácií — preplnené, alebo prehľadné?
10. Doladenie — hover, prechody, načítavanie, prázdne a chybové stavy formulárov

Každá oblasť: skóre + nálezy `súbor:riadok — problém → oprava (token)`, podobné zlúč. Nič nemeň bez súhlasu.

## Režim 3 — Generické „AI" vzory

Hľadaj a nahlás (ak nie sú súčasťou značky projektu):

- gradienty všade, fialovo-modré prechody ako default
- sklenené karty (glassmorphism) bez účelu
- zaoblenie na všetkom, aj na tabuľkách a vstupoch, kde projekt zaobľuje inak
- animácie pri scrollovaní
- hero so stredovým textom na gradiente
- nový odtieň, tieň alebo zaoblenie mimo tokenov
- emoji alebo cudzia sada ikon vedľa ikon projektu

## Overenie v prehliadači

- cache CSS: reload (ani `location.reload(true)`) ju nie vždy obíde; v konzole:
  ```js
  await Promise.all([...document.querySelectorAll('link[rel="stylesheet"]')]
    .map(l => fetch(l.href, {cache: 'reload'})));
  location.reload();
  ```
- cache šablón po prepnutí vetvy: Nette vyprázdni `temp/cache`, Symfony `php bin/console cache:clear`
  (v kontajneri z `.claude/devkit.json`, ak ho projekt má)
- over aspoň 2 šírky (mobil ~375 px, desktop) a stavy hover/focus
- dôkaz = screenshot alebo konkrétne pozorovanie, nie „malo by to fungovať"

## Výstup

- záver prvý: čo je nekonzistentné / čo si zmenil
- nálezy `súbor:riadok — problém → token/oprava`, najväčší dopad navrchu
- nové tokeny: meno · hodnota · súbor
- všetky nálezy podľa dopadu; detail (scenár, ukážka) na vyžiadanie
