---
name: ecc-seo
description: SEO server-renderovaného webu — audit indexovateľnosti (robots, canonical, sitemap, presmerovania, status kódy), title/meta/nadpisy, štruktúrované dáta JSON-LD, Core Web Vitals, interné odkazy. Pri zlepšovaní viditeľnosti vo vyhľadávaní.
---
<!-- prevzaté z ECC skills/seo/SKILL.md @ b92f181, upravené -->

# SEO — server-renderovaný web

Viditeľnosť cez technickú správnosť, výkon a relevantný obsah, nie cez triky.

## Kedy

- audit indexovateľnosti: `robots.txt`, `noindex`, canonical, presmerovania, sitemap, status kódy
- title, meta description a nadpisy v layoute a šablónach
- štruktúrované dáta (JSON-LD)
- Core Web Vitals
- nová sekcia alebo URL, zmena routera, migrácia URL
- mapovanie kľúčových slov na URL, interné odkazy

## Princípy

1. najprv technické blokery, potom obsah
2. jedna stránka = jeden jasný zámer vyhľadávania
3. dlhodobá kvalita, nie manipulácia
4. mobile-first — indexuje sa mobilná verzia
5. každé odporúčanie viazané na konkrétnu stránku a `súbor:riadok` šablóny
6. najprv skutočný výstup stránky (`curl`), až potom šablóna

## Technický checklist

### Prehľadávanie

- `robots.txt` povoľuje dôležité stránky, blokuje bezcenné (administrácia, interné vyhľadávanie,
  kombinácie filtrov) a obsahuje `Sitemap:`
- žiadna dôležitá stránka nemá omylom `noindex` — meta tag aj hlavička `X-Robots-Tag`
- dôležité stránky do ~3 klikov od úvodnej
- presmerovania max 2 skoky; trvalé = `301`/`308`, dočasné = `302`/`307`

### Indexovateľnosť

- jeden preferovaný tvar URL (https, s/bez `www`, s/bez koncového `/`), ostatné tvary `301` na neho
- `rel="canonical"` = absolútna URL stránky samej, bez sledovacích parametrov a session; bez slučiek
- stránkovanie: každá strana kanonická sama na seba, nie na stranu 1
- filtre a triedenie: `noindex` alebo canonical na základnú URL, nech nevznikajú tisíce duplicít
- viac jazykov: `hreflang` obojsmerne na všetkých jazykových verziách + `x-default`
- sitemap = len kanonické, indexovateľné URL so stavom `200`; generuj ju z dát (presenter / kontrolér
  → XML), nie ručne
- neexistujúci obsah vracia skutočný `404`/`410`, nie `200` s textom „nenájdené" (soft 404)

### Výkon (Core Web Vitals)

- LCP < 2,5 s · INP < 200 ms · CLS < 0,1
- server: TTFB (pomalé dotazy, N+1, chýbajúca cache), kompresia, dlhá cache pre assety s verziou v URL
- `<img>` s `width`/`height` (CLS); `loading="lazy"` mimo prvej obrazovky; hlavný obrázok bez lazy
  a s `fetchpriority="high"`
- blokujúce CSS/JS v `<head>` minimalizuj — ale `defer`/presun skriptov len s overením, mení poradie
  vykonania a môže rozbiť existujúci JS
- webfonty: `font-display: swap`, preload len hlavného rezu

### Štruktúrované dáta

- úvodná stránka `Organization` / `LocalBusiness` · články `Article` · produkty `Product` + `Offer` ·
  vnútorné stránky `BreadcrumbList` · `FAQPage` len ak je FAQ naozaj na stránke
- schéma opisuje len obsah, ktorý je na stránke viditeľný

## On-page

- `<title>` ~50–60 znakov, hlavná téma vpredu, unikátny pre každú stránku: `Téma – upresnenie | Značka`
- meta description ~120–160 znakov, pravdivá: akcia + téma + prínos + jeden detail
- jeden `<h1>`; `<h2>`/`<h3>` podľa obsahu, nie podľa vizuálu
- `alt` na obsahových obrázkoch, dekoratívne `alt=""`
- Open Graph (`og:title`, `og:description`, `og:image`, `og:url`) pre zdieľanie

## Šablóny (Latte / Twig)

- title, description, canonical a robots ako bloky v layoute s rozumným defaultom; stránka blok
  prepíše (Latte `{block title}`, Twig `{% block title %}`)
- default nesmie byť jeden pre všetky stránky — nájdi šablóny, ktoré blok neprepisujú (duplicitné title)
- absolútne URL: Nette `{link //Detail:default $id}` / `n:href="//…"`, Symfony `url('route', params)`
  (nie `path()`)
- canonical len z parametrov, ktoré určujú obsah (id, strana): Nette `{link //Detail:default $id}`, nie
  `{link //this}` — ten nesie aj persistentné parametre presentera a komponentov (filtre, triedenie); Symfony
  `url(app.request.attributes.get('_route'), app.request.attributes.get('_route_params'))`
- JSON-LD skladaj ako pole v PHP:
  - Latte: `<script type="application/ld+json">{$schema}</script>` — Latte pole v tomto kontexte sám
    zakóduje ako JSON a ošetrí `</`; `|noescape` netreba
  - Twig: `{{ schema|json_encode(constant('JSON_HEX_TAG'))|raw }}` — `|raw` len pre takto zakódovaný
    reťazec, nikdy pre surové dáta (XSS)
- `noindex` pre neprodukčné prostredia hlavičkou `X-Robots-Tag: noindex` podľa konfigurácie prostredia
  (Nette `http: headers:` v lokálnom/stagingovom neon, Symfony listener alebo web server), nie natvrdo
  v šablóne — inak ho deploy prenesie na produkciu alebo staging skončí v indexe
- stav a presmerovania: Nette `$this->error()` (404 cez ErrorPresenter), `$this->redirectPermanent()`;
  Symfony `throw $this->createNotFoundException()`, `$this->redirectToRoute('route', [], 301)`

## Kľúčové slová a interné odkazy

1. zámer vyhľadávania → realistické varianty → priorita podľa zhody so zámerom, hodnoty a konkurencie
2. jedna hlavná téma = jedna URL; dve stránky na tú istú tému = kanibalizácia → zlúčiť alebo odlíšiť

- odkazuj zo silných stránok na tie, ktoré majú rankovať
- popisný text odkazu, nie „viac" alebo „tu"
- nová stránka → doplň odkazy na ňu z existujúcich relevantných stránok

## Overenie

- `curl -sI https://web/stranka` — status, `Location`, `X-Robots-Tag`, cache hlavičky
- `curl -sL https://web/stranka | grep -iE '<title>|rel="canonical"|name="(description|robots)"|ld\+json'`
- reťaz presmerovaní: `curl -sIL https://web/stara-url | grep -iE '^(HTTP|location)'`
- JSON-LD: Rich Results Test alebo validator.schema.org; CWV: PageSpeed Insights alebo Lighthouse v DevTools
- `robots.txt` a `X-Robots-Tag` over na produkcii aj na stagingu

## Anti-vzory

- napchávanie kľúčových slov → píš pre ľudí
- tenké, takmer rovnaké stránky → zlúčiť alebo odlíšiť
- schéma pre obsah, ktorý na stránke nie je → schéma = realita
- rada bez prečítania stránky → najprv `curl` a šablóna
- všeobecné „zlepši SEO" → každé odporúčanie na konkrétnu stránku a súbor

## Výstup

- záver prvý: najväčší bloker indexácie alebo najväčší prínos
- nálezy podľa dopadu: `[VYSOKÁ] súbor:riadok — problém → oprava`
- všetky nálezy podľa dopadu; detail (scenár, ukážka) na vyžiadanie
