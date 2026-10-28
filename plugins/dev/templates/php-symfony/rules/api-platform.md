---
paths:
  - "src/ApiResource/**"
  - "src/State/**"
  - "src/Filter/**"
  - "src/Serializer/**"
  - "src/Entity/**"
  - "config/packages/api_platform.yaml"
---

# API Platform

- Odpoveď API je kontrakt s odberateľmi: zmena `#[Groups]`, `#[SerializedName]`, `#[ApiProperty]`, operácií alebo formátu = breaking change → over dopad a spomeň ho v commite.
- Premenovanie poľa alebo zdroja: starý názov nechaj prechodne vedľa nového; odstránenie až po dohode s odberateľmi.
- Pole sa do API dostane len cez serializačnú skupinu — interné polia do `*:read` skupín nepridávaj.
- Vlastná logika cez State Provider / Processor, nie vlastný controller; validácia cez constraints a `validationContext`.
- Bezpečnosť per operácia (`security: "is_granted('…')"`); `openapi: false` endpoint len skryje z dokumentácie, neodstráni ho.
- Filtre cez `#[ApiFilter]` / `QueryParameter`; nový query parameter zapíš aj do whitelistu parametrov, ak ho projekt má.
- Veľké kolekcie: stránkovanie a horný limit explicitne (`paginationItemsPerPage`, `paginationMaximumItemsPerPage`).
- Vlastný normalizer aktivuj len v správnom kontexte (operácia, skupiny), inak zmení aj interné serializácie (admin, export).

## Overenie

- `bin/console debug:router` (routy `_api_*`), `bin/console api:openapi:export` (aktuálny kontrakt na porovnanie pred/po).
- Test cez `ApiTestCase`: `static::createClient()->request('GET', '/api/…')` + `assertResponseIsSuccessful()`, `assertJsonContains()`.

## Pasce

- Neznáme query parametre API Platform ignoruje a vráti 200 → pri HTTP cache kľúčovanej celou URL `?x=<náhoda>` obíde cache; obrana je whitelist parametrov s odpoveďou 400.
- Po zmene kontraktu ostanú v HTTP/reverse-proxy cache staré odpovede → po deployi invaliduj dotknuté endpointy.
- Normalizer, ktorý dotahuje vzťahy po jednom, robí N+1 na každý riadok kolekcie → načítaj dávkovo pre celú stránku.
- Per-request cache v normalizeri vo worker móde prežije request → `ResetInterface`.
- Pole objektov sa v CSV výstupe rozpadne na stĺpce `pole.0.x` — pri CSV počítaj s plochou štruktúrou.
- Výmena obsahu pod existujúcim identifikátorom zdroja je tichý breaking change (HTTP 200, iné dáta).
