---
name: ecc-api-design
description: Návrh a review HTTP API — názvy zdrojov, metódy a status kódy, formát chýb, stránkovanie, filtre, verziovanie a spätná kompatibilita verejného API. Pri novom endpointe, zmene odpovede alebo review API kódu.
paths:
  - "app/**/Api*.php"
  - "app/**/Api/**"
  - "src/Api/**"
  - "src/ApiResource/**"
  - "src/Controller/Api/**"
  - "src/State/**"
  - "config/packages/api_platform*"
  - "**/openapi*.{yaml,yml,json}"
---
<!-- prevzaté z ECC skills/api-design/SKILL.md @ b92f181, upravené -->

# Návrh API — konzistentné a spätne kompatibilné

## Kedy

- nový endpoint alebo akcia v API presenteri / kontroléri / API Platform zdroji
- zmena tvaru odpovede (pole, typ, formát dátumu, XML element, serializačná skupina)
- stránkovanie, filtre, triedenie, chyby, autentifikácia, rate limit
- review API kódu, plán verziovania alebo ukončenia starej verzie

## Najprv zisti kontrakt

- **kto API volá**: vlastný frontend, iná appka tímu, alebo externí odberatelia → externí = každá zmena
  odpovede je riziko, ktoré sa prejaví až u nich
- **kde je kontrakt**: OpenAPI spec, XSD, dokumentácia, `#[Groups]`, testy odpovedí; ak nič z toho
  neexistuje, kontraktom je **dnešná odpoveď**
- **konvencie projektu majú prednosť** pred touto šablónou (camelCase vs. snake_case, obálka `data`,
  formát chýb, formát v URL vs. `Accept`) — nový endpoint vyzerá ako susedné

## Zdroje a URL

- podstatné mená v množnom čísle, malé písmená, kebab-case: `/api/v1/team-members`, `/api/v1/users/{id}/orders`
- filtre v query (`?status=active`); akcie mimo CRUD striedmo: `POST /api/v1/orders/{id}/cancel`
- zle: `/api/getUsers`, `/api/user`, `/api/team_members`, `/api/users/123/getOrders`

## Metódy a status kódy

| Metóda | Idempotentná | Použitie |
|---|---|---|
| GET | áno | čítanie, bez vedľajších účinkov |
| POST | nie | vytvorenie, spustenie akcie |
| PUT | áno | úplná náhrada |
| PATCH | nie (dá sa) | čiastočná zmena |
| DELETE | áno | odstránenie |

- `200` čítanie/úprava s telom · `201` + `Location` po vytvorení · `204` bez tela
- `400` zlý vstup, neznámy parameter · `401` chýba/zlá autentifikácia · `403` prihlásený bez práva ·
  `404` neexistuje · `409` konflikt stavu, duplicita · `422` neplatné dáta · `429` limit + `Retry-After`
- `500` nikdy s detailom (stack trace, SQL) · `503` + `Retry-After` pri údržbe
- zle: `200` s `{"success": false}`; `500` pri chybe validácie; `200` po vytvorení

## Formát chýb

- jeden formát pre celé API; Symfony / API Platform má natívne Problem Details
  (`application/problem+json`, RFC 9457) — použi ho, ak ho projekt používa
- inak napr.:
  ```json
  {"error": {"code": "validation_error", "message": "Neplatný vstup",
    "details": [{"field": "email", "code": "invalid_format", "message": "Neplatný e-mail"}]}}
  ```
- `code` je strojovo stabilný (klient na ňom vetví), `message` je pre človeka
- chyba API ide vo formáte API (JSON/XML), nie ako HTML chybová stránka

## Stránkovanie, filtre, triedenie

- každý zoznam stránkuj; predvolený aj maximálny limit (napr. 50 / 500)
- offset (`?page=2&per_page=20`): jednoduchý, skok na stranu N; pomalý pri veľkom `OFFSET`, pri
  súbežných zápisoch sa záznamy posúvajú
- keyset/kurzor (`?after_id=123&limit=20` → `WHERE id > ? ORDER BY id LIMIT 21`): stabilný a rýchly pri
  veľkých dátach, bez skoku na stranu; 21. riadok = `has_next`
- vždy deterministické `ORDER BY` (na konci unikátny stĺpec), inak sa záznamy medzi stranami opakujú
- `total` len ak je lacný — `COUNT(*)` nad veľkou tabuľkou stojí; inak `has_next`
- triedenie `?sort=-created_at,name`; filtre aj triedenie len cez whitelist stĺpcov — názov stĺpca
  z requestu nikdy nejde do SQL
- verejné API za reverse-proxy cache: cache kľúčuje podľa celej URL → neznáme query parametre
  odmietni (`400`), inak ich ktokoľvek použije na obchádzanie a nafukovanie cache

## Autentifikácia a autorizácia

- token v hlavičke (`Authorization: Bearer …`, `X-API-Key`), nie v URL — URL končí v logoch a histórii
- token náhodný a dlhý (`bin2hex(random_bytes(32))`), porovnanie `hash_equals()`, v DB ideálne hash
- **autorizácia na úrovni záznamu**: volajúci smie práve tento záznam (vlastník, organizácia), nie len
  „je prihlásený"; test s cudzím záznamom
- ak je citlivá už samotná existencia záznamu, vráť `404` namiesto `403`
- ACL / firewall musí kryť aj API routy; zakomentovaná kontrola = otvorené API
- rate limit na verejné a prihlasovacie endpointy (`429` + `Retry-After`)

## Spätná kompatibilita

Nerozbíja (bez novej verzie): nové voliteľné pole v JSON, nový voliteľný parameter, nový endpoint.

Rozbíja (nová verzia alebo prechodné obdobie):
- odstránenie/premenovanie poľa alebo XML elementu, zmena typu (`"1"` → `1`, `null` → chýbajúci kľúč)
- zmena formátu dátumu/čísla, významu hodnoty, URL, autentifikácie, poradia, na ktoré sa klient spolieha
- nová povinná položka vstupu
- **XML so schémou**: klient validujúci striktným XSD padne aj na **pridanom** elemente → oznámiť aj pridanie
- nová hodnota enumu/číselníka rozbije klienta so `switch` bez defaultu → oznámiť

Postup pri nutnej zmene:
1. nový tvar **popri** starom (nové pole/blok alebo `/v2`), starý ostáva bajt po bajte rovnaký
2. oznámiť odberateľom; na starom tvare hlavičky `Deprecation` a `Sunset`
3. starý tvar odstrániť až po prechodnom období, ktoré určí vlastník API, nie vývojár
- max 2 aktívne verzie; verzia v URL (`/api/v1/`) je najprehľadnejšia

Nepriame zmeny kontraktu (ľahko sa prehliadnu):
- premenovanie kľúča poľa, z ktorého sa generuje názov XML uzla alebo JSON kľúča
- pridanie `#[Groups]` / `#[SerializedName]` / `#[ApiProperty]`, zmena normalizera
- zmena typu stĺpca v DB (`INT` → `DECIMAL` = v PHP string, v JSON `"1.00"` namiesto `1`), zmena DB
  vrstvy (iný typ dátumu)
- dátumy kontroluj cez `\DateTimeInterface`, nie `\DateTime` — `DateTimeImmutable` inak ticho
  prejde inou vetvou a zmení formát výstupu

## Implementácia — Nette

- odpoveď `$this->sendJson($data)`; status `$this->getHttpResponse()->setCode(422)` pred odoslaním
- `$this->error()` v API presenteri skončí v ErrorPresenteri ako HTML → v API vráť chybu vo formáte API
- `sendJson()`/`sendResponse()` končia `AbortException` (potomok `\Exception` vo všetkých
  verziách Nette 3) → nechytaj ju všeobecným `catch (\Exception $e)`, inak sa odpoveď stratí
- vstup `$this->getHttpRequest()->getRawBody()` + `json_decode($body, true, 512, JSON_THROW_ON_ERROR)`
  (pozičné argumenty fungujú aj na PHP 7.4), potom explicitná validácia (Nette Schema, ak ju projekt má)
- ACL kontrola v `startup()` aj pre API presenter; tokenové API bez cookies CSRF nepotrebuje, API so
  session cookie áno

## Implementácia — Symfony

- `#[MapRequestPayload]` / `#[MapQueryString]` (Symfony ≥ 6.3) + Validator → neplatný vstup = `422` automaticky
- `$this->json($data, 201, ['Location' => $url])`; serializačné skupiny explicitné (`#[Groups(['x:read'])]`)
- API Platform: `#[Groups]`/`#[ApiProperty]` na property = zmena verejného kontraktu; `openapi: false`
  skryje dokumentáciu, nie endpoint
- `security:` na operácii alebo `#[IsGranted]` aj pre čítanie; firewall pre `^/api` v `security.yaml`
- HTTP cache (`HttpCache`, reverse proxy): zmena kontraktu = invalidácia cache po deployi

## Test kontraktu

- integračný test reprezentatívneho requestu: status, hlavičky, presný tvar tela (kľúče, typy, formát
  dátumu) — zmena odpovede ho zámerne zhodí
- testy `401`, `403`/`404` na cudzí záznam, neplatný vstup, neznámy parameter
- XML: validácia výstupu voči XSD v teste, ak schéma existuje

## Checklist pred odovzdaním

- [ ] URL, metóda a pomenovanie podľa konvencií projektu
- [ ] status kódy sémanticky, nie `200` pre všetko
- [ ] vstup validovaný, chyby v jednotnom formáte, bez interných detailov
- [ ] zoznamy stránkované, s limitom a deterministickým poradím
- [ ] autentifikácia (alebo výslovne verejné) + autorizácia na úrovni záznamu + rate limit
- [ ] spätná kompatibilita overená; rozbíjajúca zmena → postup vyššie
- [ ] test kontraktu, dokumentácia (OpenAPI / XSD / README) aktualizovaná
- [ ] cache invalidovaná, ak sa zmenil kontrakt

## Výstup

- záver prvý: je zmena spätne kompatibilná — áno/nie a prečo jednou vetou
- nálezy `súbor:riadok — problém → oprava`, rozbíjajúce zmeny a bezpečnosť navrchu
- všetky nálezy podľa dopadu; detail (scenár, ukážka) na vyžiadanie
