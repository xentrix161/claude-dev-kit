---
paths:
  - "tests/**"
  - "phpunit.xml*"
  - "playwright.config.*"
---

# Testy

## Sady (typické; skutočné názvy v `phpunit.xml`)

- `unit` — izolované triedy bez DB a DI kontajnera (testovateľný wrapper s prázdnym konštruktorom).
- `integration` — modely, presentery, autentifikácia nad reálnou DB; každý test beží v transakcii → `ROLLBACK`.
- `smoke` — HTTP požiadavky na bežiacu appku (200, nie 500); potrebuje credentials.
- `e2e` — Playwright v `tests/e2e/`; auth setup uloží session, ostatné testy ju použijú.
- Presné príkazy: CLAUDE.md (Príkazy) a `.claude/devkit.json` (`check.steps`).

## Písanie testov

- Nová funkcionalita → test; oprava bugu → test, ktorý by bug odhalil (najprv červený, potom oprava).
- AAA (arrange, act, assert), jeden dôvod zlyhania na test, názov opisuje scenár.
- Base triedy, pomocníkov a umiestnenie preber od susedných testov; novú infraštruktúru nezavádzaj.
- Dáta si test vytvorí sám vo svojej transakcii — nespoliehaj sa na záznamy v lokálnej DB.
- Dátumy fixuj na konkrétnu hodnotu, nie „teraz" — hranice mesiaca a roka inak padajú náhodne.

## Integračné testy a transakcie

- Integračná base trieda otvára transakciu v `setUp()` a v `tearDown()` robí `rollback()` — nový test ju dedí, nie vlastné pripojenie.
- Testovaný kód nesmie volať `begin()`/`commit()` ani DDL — MySQL implicitne commitne a test zapíše natrvalo.
- Triggery zapisujú aj v teste; po rollbacku zmiznú, ale v aserciách s nimi počítaj.

## E-maily, SMS, externé služby

- V test configu musia byť nahradené atrapou, ktorá správy len zbiera — žiadny test nesmie poslať reálny mail ani SMS.
- Nový odosielací kanál = najprv atrapa v test configu, potom test.
- Atrapu resetuj v `setUp()`, inak sa počty prenášajú medzi testami.

## Credentials

- `.test-credentials` (kópia `.test-credentials.stub`) nie je v gite; hodnoty nikdy nevypisuj ani necommituj.
- Uložená Playwright session (`.auth/`) nie je v gite.

## Overenie

- Spúšťaj v kontajneri cez `docker exec` **bez `-it`**.
- Do odpovede vlož súhrnný riadok: `OK (N tests, M assertions)` alebo `FAILURES! Tests: N, Failures: F`.
- Padá test → oprav kód, nie test. Test meníš len keď je zlý — povedz prečo a nechaj to potvrdiť.
- Nikdy `markTestSkipped()`, zmazaná asercia ani `--filter` na zakrytie zlyhania.

## Pasce

- `make test*` s `docker exec -it` bez TTY padne: „the input device is not a TTY".
- Test bez asercie je „risky" a pri `failOnRisky="true"` je celý beh neúspešný.
- Integračný test zelený len vďaka dátam v lokálnej DB padne u kolegu aj v CI.
- `COUNT(*)` nad celou tabuľkou v asercii je krehký → porovnávaj rozdiel alebo vlastné záznamy.
- Smoke a E2E pri nebežiacej appke alebo chýbajúcich credentials padajú — to je SKIP, nie dôvod meniť kód.
- Statický stav (singleton, atrapa mailera) prežíva medzi testami v jednom procese.
