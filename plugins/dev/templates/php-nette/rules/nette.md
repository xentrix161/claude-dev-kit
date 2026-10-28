---
paths:
  - "app/**"
  - "libs/**"
---

# Nette — presentery, DI, formuláre, ACL

## Presentery

- Tenké: vstup → model/služba → šablóna. SQL a biznis logika patria do modelov a služieb.
- Prihlásené stránky dedia od spoločného base presentera (jeho `startup()` overuje login a ACL), nie priamo od `Nette\Application\UI\Presenter`.
- `action*`/`render*` cez GET dáta nemenia (odkaz, prefetch, crawler) — zmena ide cez formulár (POST) alebo signál `handle*`.
- Po úspešnom POST `flashMessage()` + `redirect()` (PRG), nie priame vykreslenie.
- `getParameter()`, `$_GET`, `$_POST` sú nedôveryhodný vstup → typované parametre akcie, validácia, whitelist.

## DI a konfigurácia

- Služby registruj v `app/config/*.neon`, do tried ich dávaj konštruktorom; žiadne `$container->getService()` v kóde.
- `inject*` metódy a `#[Inject]` len v presenteroch a len ak ich projekt už používa.
- Nový konfiguračný kľúč → doplň aj vzor lokálneho configu (stub), inak kolegovi appka nenabehne.
- `config.local.neon` (heslá, API kľúče) nikdy necommituj ani nevypisuj.

## Formuláre a CSRF

- Formulár, ktorý mení stav, má `$form->addProtection()`.
- `allowCrossOrigin()` na formulári ani `#[CrossOrigin]` na signáli nepridávaj bez jasného dôvodu.
- Hodnoty ber z `$form->getValues()` (validované), nie z `$httpRequest->getPost()`.
- Validácia vždy na serveri; JS validácia je len pohodlie.

## Autorizácia (ACL)

- Každú akciu a signál kryje `$this->getUser()->isAllowed($resource, $privilege)` — centrálne v `startup()` base presentera alebo v metóde; skryté tlačidlo nie je ochrana.
- Nový presenter alebo akcia = nový resource/privilege tam, kde projekt ACL definuje (migrácia alebo `Permission` v kóde), a priradenie rolám.
- Prístup k záznamu inej organizácie či používateľa over aj pri povolenom privilégiu (IDOR).

## CLI a cron

- Dlhé joby: zámok proti súbežnému behu, idempotentné kroky, výstup do logu, nie na obrazovku.

## Pasce

- `redirect()`, `forward()`, `sendJson()`, `terminate()` hádžu `AbortException` → `catch (\Exception|\Throwable)` okolo nich ju zhltne a kód beží ďalej.
- `temp/cache` drží DI kontajner a Latte; v produkčnom móde sa po zmene `.neon` neprebuduje → vyčisti ho.
- `onSuccess` formulára beží po `action*` a pred `render*` — premenné z `render*` v ňom ešte nie sú.
- `#[Persistent]` parametre sa prenášajú do všetkých odkazov presentera → nečakané filtre na iných stránkach.
- `isLoggedIn()` nie je autorizácia — prihlásená rola nemusí mať právo na akciu.
