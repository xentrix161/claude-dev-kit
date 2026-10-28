---
paths:
  - "src/**"
  - "config/**"
---

# Symfony

- Konfigurácia atribútmi, nie YAML ani docblock anotáciami: `#[Route]`, `#[AsCommand]`, `#[AsEventListener]`, `#[AsMessageHandler]`, `#[Autowire]`, `#[IsGranted]`.
- Vstup requestu cez `#[MapRequestPayload]`, `#[MapQueryString]`, `#[MapQueryParameter]` + Validator, nie ručné `$request->get()`.
- Služby: autowire + autoconfigure z `config/services.yaml`; do YAML len parametre a to, čo autowiring nevyrieši.
- Závislosti len cez konštruktor; nikdy `$container->get()` ani service locator v doméne.
- Controller tenký: vstup → služba → `Response`; logika v službách, dotazy v repozitároch.
- Autorizácia cez `#[IsGranted]` alebo voter (`isGranted('EDIT', $obj)`), nie ručné porovnávanie rolí.
- CSRF: Symfony Form ho má zapnutý; ručný `<form>` so zmenou stavu → `csrf_token('id')` + `isCsrfTokenValid()`; mazanie nikdy cez GET.
- Prostredie cez `%env(NAZOV)%` / `#[Autowire(env: 'NAZOV')]`; tajomstvá v `.env.local` alebo vo vaulte (`secrets:set`), `.env` v gite len defaulty.
- Konzolové príkazy: `#[AsCommand]`, návrat `Command::SUCCESS`/`Command::FAILURE`, výstup cez `SymfonyStyle`.
- Mail a notifikácie len cez Mailer/Notifier; dev/test mieria na atrapu (`null://null`, Mailpit), nikdy na reálnych príjemcov.
- Zmena v `config/` → `lint:container` a `lint:yaml config --parse-tags`.

## Overenie

- `bin/console lint:container` → `[OK] The container was linted successfully: …`
- `bin/console debug:router <route>` · `debug:container <id>` · `debug:autowiring <typ>` · `debug:event-dispatcher <event>`

## Pasce

- Worker mód (FrankenPHP, RoadRunner): stav v službe prežije request → per-request cache implementuje `ResetInterface`, inak dáta pretečú medzi používateľmi.
- Po zmene `.env*`, `config/` alebo prepnutí vetvy drží dev starú cache → `cache:clear`.
- Priorita event subscriberov určuje poradie (bezpečnosť, cache hlavičky, whitelisty) → nový listener over cez `debug:event-dispatcher`.
- Všeobecnejšia routa načítaná skôr prebije špecifickú → `priority` v `#[Route]`, over `debug:router`.
- `ChoiceType` ticho zahodí uloženú hodnotu, ktorá nie je medzi `choices` → do volieb pridaj aj aktuálnu hodnotu záznamu.
- Odpoveď na request, ktorý naštartoval session (aj stateful firewall), dostane `Cache-Control: private` → HttpCache ani reverse proxy ju necachujú; verejné cachované routy drž bez session.
- `cache:clear` maže len `var/cache/<env>` — dáta, ktoré majú prežiť deploy (napr. store HttpCache), drž mimo neho.
- Dlhý command s Doctrine bez dávkového `clear()` rastie v pamäti; v dev ešte viac (profiler, debug) → `--no-debug`.
- Rovnaká logika na dvoch miestach (napr. cache pravidlo a whitelist ciest) sa rozíde ticho → jedna služba alebo test, ktorý ich porovná.
