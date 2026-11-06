---
paths:
  - "templates/**"
  - "assets/**"
  - "**/*.twig"
  - "importmap.php"
  - "webpack.config.js"
---

# Twig a frontend

- Twig escapuje sám; `|raw` len na obsah zo sanitizéra (`|sanitize_html`, HtmlSanitizer) a s dôvodom — hook ho hlási.
- URL cez `path()`/`url()`, súbory cez `asset()`; žiadne natvrdo písané cesty.
- Texty cez `|trans` / `{% trans %}` a `translations/`, ak projekt prekladá.
- Formuláre cez `form_start`/`form_row`/`form_end` (CSRF token, label, chyby); ručný `<form>` potrebuje `csrf_token()` sám.
- Bez `{{ dump() }}` a `{% dump %}` v commitnutých šablónach.
- `console.log`/`console.debug` a priradenie do `innerHTML` v `.js`/`.ts` hook hlási (guardy `console-log`, `inner-html`); text vkladaj cez `textContent`.
- Logika patrí do controllera alebo Twig extension, nie do šablóny (žiadne dotazy ani zložité výpočty).
- AssetMapper: balíky cez `importmap:require` len so súhlasom; `assets/vendor/` je stiahnutý vendor — needituje sa. <!-- fe:assetmapper -->
- Webpack Encore: assety v Twig cez `encore_entry_link_tags()`/`encore_entry_script_tags()`, nie natvrdo `/build/…`; balík (`npm install <balík>`) len so súhlasom, `package.json` a lock súbor commitni spolu; `public/build/` je výstup buildu — needituje sa. <!-- fe:encore -->
- Nové CSS cez existujúce tokeny projektu (CSS premenné), nie magické čísla; nový `!important` len s dôvodom.
- JS kotvy (`data-controller`, `data-action`, `data-*-target`, sémantické triedy) sú kontrakt — pri zmene markupu ich zachovaj a cieľ na sémantickú triedu, nie na pozíciu súrodenca.
- Prístupnosť: každý vstup má `label`, tlačidlo len s ikonou má `aria-label`, informácia nikdy len farbou.

## Overenie

- `bin/console lint:twig templates` → `[OK] All … Twig files contain valid syntax.` (po edite `.twig` beží na súbor sám).
- Po čerstvom klone alebo zmene `importmap.php`: `bin/console importmap:install` stiahne `assets/vendor/` (exit 0). <!-- fe:assetmapper -->
- Po zmene v `assets/`: `npm run build` skončí exit 0 bez `ERROR in`; bez buildu prehliadač dostane starý `public/build/`. <!-- fe:encore -->
- Má projekt eslint či stylelint, `/dev:check` ich púšťa nad zmenenými `.js`/`.ts`, resp. `.css`/`.scss` (kroky `eslint`, `stylelint`).
- Vizuálna zmena: hard reload v prehliadači a preklik dotknutej stránky alebo formulára.

## Pasce

- Existujúci `public/assets/` (po `asset-map:compile`) má prednosť aj v dev → zmeny v `assets/` nevidno, kým ho nezmažeš. <!-- fe:assetmapper -->
- `manifest.json` a `entrypoints.json` v `public/build/` sú z posledného buildu → po prepnutí vetvy `npm run build`, inak Twig odkazuje na staré súbory. <!-- fe:encore -->
- Prehliadač drží hash assetu z inej vetvy → hard reload (Cmd+Shift+R); pri prepínaní vetiev aj `cache:clear`.
- Rozbitý JS selektor zlyhá ticho (prázdna kolekcia nehádže, HTTP 200, čistá konzola) → po zmene markupu preklikni dotknutý formulár.
- `|raw` na preklade s HTML robí z prekladu dôveryhodný vstup — používateľské dáta doň nevkladaj.
- `{% include %}` odovzdá celý kontext; izolácia cez `with {…} only`.
- Poradie CSS rozhoduje: nový override patrí za štýl, ktorý prepisuje, inak potrebuje `!important`.
