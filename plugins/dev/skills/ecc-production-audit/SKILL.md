---
name: ecc-production-audit
description: "Audit pripravenosti na produkciu z lokálnych dôkazov: bezpečnosť, migrácie, integrácie, prevádzka, návrat. Pred nasadením alebo po merge."
argument-hint: "[base-vetva]"
disable-model-invocation: true
allowed-tools:
  - 'Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/check.sh" *)'
---
<!-- prevzaté z ECC skills/production-audit/SKILL.md @ b92f181, upravené -->

# Audit pripravenosti na produkciu

Inžinierske triedenie rizík z lokálnych dôkazov, nie certifikácia ani právny audit. Výsledok = skóre, blokujúce body, jeden ďalší krok. Komunikuj po slovensky.

## Hranice
- len lokálne a používateľom povolené dôkazy; žiadne vzdialené skenery, `@latest` balíky ani odosielanie kódu či dát tretím stranám bez výslovného súhlasu s konkrétnym nástrojom
- `composer audit` posiela zoznam balíkov na Packagist → len so súhlasom
- nič nenasadzuj, nemeň konfiguráciu prostredí, nespúšťaj migrácie
- nasadené URL len na čítanie (HTTP hlavičky, health check), bez prihlásenia, kým nedostaneš testovací účet
- tajomstvá nevypisuj — stačí `súbor:riadok obsahuje heslo`

## Postup
1. Rozsah — base vetva: `$ARGUMENTS`; prázdne → `master`, ak existuje (`git rev-parse --verify -q master`), inak `main`
   ```bash
   git status --short --branch
   git log --oneline --decorate -20
   git diff --stat <base>...HEAD
   ```
2. Kontroly kitu (Bash timeout 600000 ms, beží aj integračné testy):
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/check.sh" --full --project "${CLAUDE_PROJECT_DIR}"`
   - exit 0 = PASS · 1 = FAIL · 3 = chýba `.claude/devkit.json` · 4 = nič nebežalo; PASS tvrď len podľa výstupu
3. Prejdi oblasti nižšie len tam, kde ich repozitár naozaj má; každé tvrdenie opri o `súbor:riadok` alebo príkaz
4. Výstup podľa šablóny dole

## Oblasti rizika
**Bezpečnosť a prístup**
- autorizácia na serveri pri každej akcii a signáli (Nette ACL / `isAllowed()`, Symfony `#[IsGranted]` / votery), nie len skryté tlačidlo
- CSRF na formulároch a signáloch meniacich stav; `|noescape` (Latte 2 `{!$x}`) / `|raw` len so sanitizáciou
- SQL len parametrizované; upload: typ, veľkosť, úložisko mimo `www/` / `public/`
- tajomstvá mimo repozitára (`config.local.neon`, `.env.local`), nie v logoch ani na chybových stránkach
- produkčný režim: Tracy `debugMode` vypnutý / `APP_ENV=prod` + `APP_DEBUG=0`; `display_errors=Off`
- cookies `Secure`, `HttpOnly`, `SameSite`; hlavičky HSTS, CSP, `frame-ancestors`
- prihlásenie: obmedzenie pokusov, MFA tam, kde ho appka má, žiadne heslá v logu

**Dáta a migrácie**
- migrácie prejdú čisto na kópii produkčnej schémy; poradie migrácia ↔ kód pri nasadení je dané
- deštruktívne kroky (DROP, zmena typu, backfill) po etapách; DDL v MySQL rollback nevráti → záloha + návratový postup
- triggery, fulltextový index, cache: treba preindexovať alebo vyčistiť?
- opakované spustenie cronu, dávky či importu je idempotentné; súbežné behy blokuje zámok

**Integrácie**
- externé HTTP volania majú timeout a ošetrené zlyhanie
- e-mail a SMS: produkčný transport, nie dev zachytávač; dev a test prostredie neposielajú reálne správy
- webhooky a callbacky: overený podpis, idempotencia, opakované doručenie

**Prevádzka**
- nasadenie zo zdokumentovaných príkazov: `composer install --no-dev --optimize-autoloader`; verzia PHP na serveri = `require.php` v `composer.json`
- cache pri nasadení (Nette `temp/cache`, Symfony `cache:clear`); verzovanie CSS/JS proti cache prehliadača
- monitoring chýb zapnutý; logy zapisovateľné, bez osobných údajov a hesiel
- health check overí DB a kľúčové služby (fulltext, fronta, mail)
- kto rieši incident a ako vrátiť nasadenie (predchádzajúci tag/image)

**Používateľ**
- kritické cesty prejdené end-to-end (prihlásenie, hlavný formulár, export/import) — skill `ecc-e2e-testing`
- prázdne, chybové a „nemáte oprávnenie" stavy povedia, čo sa stalo a čo ďalej
- prístupnosť kľúčových stránok — skill `ecc-accessibility`

## Skóre
Skóre núti k prioritám, nie je to presné meranie.

| Pásmo | Skóre | Význam |
|---|---|---|
| Blokované | 0–49 | nenasadzovať, kým sa neopravia hlavné riziká |
| Rizikové | 50–69 | len obmedzené nasadenie alebo interný test |
| Nasaditeľné s výhradami | 70–84 | ak vlastník prijme vymenované riziká |
| Silné | 85–100 | z dostupných dôkazov žiadny blokujúci bod |

Strop **69**, ak platí čokoľvek z:
- chýba autorizácia nad citlivými dátami
- migráciu nejde bezpečne spustiť alebo pri zásadnej zmene chýba návratový postup
- tajomstvá sú v repozitári, logoch alebo na klientovi
- debug režim alebo dev transport mailov/SMS v produkčnej konfigurácii
- dávky, importy alebo webhooky, ktoré menia dáta, nie sú idempotentné

Strop **84**, ak `check.sh --full` nie je PASS alebo kritická cesta nebola overená end-to-end.

## Výstup
Prvý riadok:
```text
Produkčný audit: 72/100 — nasaditeľné s výhradami; riziká: chýba návrat migrácie 20261020_x, cron import nemá zámok.
```
Potom sekcie (odrážky so `súbor:riadok`):
- **Blokujúce** — `súbor:riadok — problém → oprava`
- **Oplatí sa opraviť** — ďalšie kroky na vyššie skóre
- **Overené** — súbory, príkazy, výsledok `check.sh`
- **Chýba dôkaz** — čo by zmenilo istotu
- **Ďalší krok** — jeden konkrétny
- silné stránky najviac jedna odrážka

## Anti-vzory
- skóre bez vymenovaných dôkazov
- zelené testy = pripravené na produkciu
- vzdialený skener alebo upload kódu ako predvolená cesta
- záver „dajte vedieť, čo ďalej" namiesto konkrétneho kroku
