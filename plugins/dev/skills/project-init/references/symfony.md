# Detekcia nástrojov pre Symfony

| Čo | Ako | Výsledok |
|---|---|---|
| frontend a API (php-symfony) | `composer.json` `require`: `symfony/asset-mapper` → AssetMapper, `symfony/webpack-encore-bundle` → Encore (oba → oba varianty); balík `api-platform/*` (napr. `api-platform/core`) → API Platform | riadky `<!-- fe:assetmapper -->` / `<!-- fe:encore -->` v `AGENTS.md.tmpl` a `rules/twig-frontend.md`; `rules/api-platform.md` a riadky `<!-- api-platform -->` len s API Platform |
