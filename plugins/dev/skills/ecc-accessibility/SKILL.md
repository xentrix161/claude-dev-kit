---
name: ecc-accessibility
description: "Prístupnosť WCAG 2.2 AA v šablónach Latte/Twig a CSS: sémantika, formuláre, fokus, klávesnica, kontrast, ARIA. Pri tvorbe, zmene a audite UI."
paths:
  - "**/*.latte"
  - "**/*.twig"
  - "www/css/**"
  - "assets/**/*.css"
  - "templates/**"
---
<!-- prevzaté z ECC skills/accessibility/SKILL.md @ b92f181, upravené -->

# Prístupnosť (WCAG 2.2 AA)

## Kedy
- nová alebo upravená šablóna, formulár, modal, tabuľka, menu
- zmena CSS: farby, fokus, veľkosti (kontrast, cieľová plocha)
- audit stránky pred odovzdaním — weby verejnej správy: smernica EÚ 2016/2102 → EN 301 549 → minimálne WCAG 2.1 AA; 2.2 pridáva 2.4.11, 2.5.7, 2.5.8, 3.2.6, 3.3.7, 3.3.8

## Princíp
- natívny HTML prvok pred ARIA: `<button>`, `<a href>`, `<label>`, `<table>`, `<nav>` majú rolu, klávesnicu aj fokus zadarmo
- ARIA len dopĺňa, čo HTML nevie (`aria-expanded`, `aria-live`, `aria-current`); zlá ARIA je horšia ako žiadna
- POUR: vnímateľné, ovládateľné, zrozumiteľné, robustné — každý nález zaraď k číslu kritéria (napr. 1.3.1)

## Stránka
- `<html lang="sk">`; úsek v inom jazyku `lang="en"` na prvku
- jedinečný `<title>` na stránku (blok v layoute), jedno `<h1>`, nadpisy bez preskakovania úrovní
- orientačné body: `<header>`, `<nav aria-label="Hlavné menu">`, `<main id="obsah">`, `<footer>`; „Preskočiť na obsah" ako prvý fokusovateľný prvok
- aktívna položka menu a breadcrumbs: `aria-current="page"`
- konzistentná navigácia a pomoc na rovnakom mieste naprieč stránkami (3.2.3, 3.2.6)

## Formuláre
- každý vstup má `<label for>` (Latte `n:name` na `<label>` aj `<input>`, Twig `form_label`) — `placeholder` nie je label
- povinné pole: `required`, nie len hviezdička alebo farba
- chyba pri poli: text chyby, `aria-invalid="true"`, `aria-describedby` na prvok s chybou; pri viacerých chybách zhrnutie hore s odkazmi na polia
- chybová hláška hovorí, ako to opraviť (3.3.3), nie len „neplatná hodnota"
- `autocomplete` pri osobných údajoch a prihlásení (`username`, `current-password`, `one-time-code`, `email`) (1.3.5)
- prihlásenie (3.3.8): povoliť vkladanie hesla a správcov hesiel, žiadne blokovanie `paste`; prepisovanie kódu z obrázka len s alternatívou
- nežiadaj znova údaje zadané v tom istom procese (3.3.7) — predvyplň alebo ponúkni výber
- skupiny radio/checkbox: `<fieldset>` + `<legend>`

## Obsah
- obrázok: `alt` s významom; dekoratívny `alt=""`; bez „Obrázok…" na začiatku
- tlačidlo len s ikonou: `<i class="bi bi-trash" aria-hidden="true"></i><span class="visually-hidden">Zmazať</span>` alebo `aria-label` na tlačidle
- dátové tabuľky: `<caption>`, `<th scope="col">` / `scope="row"`; tabuľky nie na rozloženie
- odkaz s výstižným textom (nie „klikni sem"); otvorenie v novom okne oznám v texte
- význam nie len farbou (stav, chyba, povinné pole) — aj text alebo ikona s textom
- hlášky vkladané cez JS/AJAX: kontajner s `role="status"` (info) alebo `role="alert"` (chyba) je v DOM ešte pred vložením textu
- flash po redirecte (celá stránka): na začiatku `<main>` pri `<h1>` — živý región s textom už pri načítaní čítačka spoľahlivo neohlási

## Interakcia a fokus
- všetko ovládateľné klávesnicou (Tab, Shift+Tab, Enter, medzerník, Esc); `div`/`span` s `onclick` → `<button type="button">`
- viditeľný fokus (2.4.7): nikdy `outline: none` bez náhrady; `:focus-visible` s kontrastom aspoň 3:1
- fokus nezakrytý (2.4.11): sticky hlavička alebo cookie lišta neprekryje fokusovaný prvok → `scroll-padding-top`
- modal: fokus dnu pri otvorení, uväznený vnútri, Esc zatvorí, fokus späť na spúšťač (Bootstrap 5 to robí — nerozbiť vlastným JS)
- dropdown, collapse, tab: `aria-expanded` / `aria-selected` sledujú stav (Bootstrap 5 cez `data-bs-*`)
- AJAX prekreslenie (snippet, filter): presuň fokus na výsledok alebo oznám zmenu cez `aria-live="polite"`
- ťahanie myšou má alternatívu jedným klikom (2.5.7)
- časový limit relácie: upozorni vopred a dovoľ predĺžiť (2.2.1)
- `tabindex` len `0` alebo `-1`; kladné hodnoty rozbijú poradie

## CSS
- kontrast textu ≥ 4,5:1; veľký text (≥ 24 px, tučný ≥ 18,7 px), ikony, okraje polí a fokus ≥ 3:1 — pri zmene značkovej farby over aj `:hover`, `:disabled`, placeholder, text na farebnom tlačidle
- cieľová plocha ≥ 24×24 CSS px alebo dostatočný odstup (2.5.8)
- reflow: šírka 320 px / zoom 400 % bez horizontálneho posuvu (okrem dátových tabuliek); zväčšenie textu na 200 % nič neoreže
- `@media (prefers-reduced-motion: reduce)` vypne animácie a plynulé posúvanie
- skryté len vizuálne: `.visually-hidden` (Bootstrap 5; v BS4 `.sr-only`), nie `display: none` (skryje aj čítačke)

## Pasce
- Select2, Chosen, jQuery UI datepicker: over klávesnicu aj čítačku; `<label>` musí ukazovať na prvok, ktorý reálne dostane fokus
- `title` atribút nie je prístupný popis (dotyk ani klávesnica ho neukážu)
- `aria-hidden="true"` na kontajneri s fokusovateľným obsahom = fokus na neviditeľnom prvku
- `role="button"` na `<a>` bez obsluhy medzerníka; `<a>` bez `href` nie je fokusovateľný
- HTML z WYSIWYG editora (`|noescape`/`|raw` po sanitizácii): sanitizér nesmie zahadzovať `alt`, nadpisy a `lang`

## Overenie
- klávesnica: prejdi stránku len Tabom — poradie, viditeľný fokus, nič neuviazne
- čítačka: macOS VoiceOver (Cmd+F5), rotor nadpisov, orientačných bodov a formulárových prvkov
- zoom 400 % a šírka okna 320 px
- automaticky: Lighthouse alebo axe DevTools v prehliadači; v Playwright E2E `@axe-core/playwright` — automatika nájde len časť problémov, ručnú kontrolu nenahrádza
- audit celej stránky alebo sady šablón: agent `dev:ecc-a11y-architect`

## Výstup
- prvý riadok: `A11y: <n> blokujúcich · <n> ďalších` + rozsah (šablóny, stránka)
- nález: `šablóna.latte:42 — problém (WCAG 1.3.1) → oprava`
- najprv blokujúce (klávesnica, chýbajúce labely a názvy, kontrast, pasca fokusu), potom ostatné
