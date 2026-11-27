---
name: commit
description: "Pripraví commit podľa pravidiel projektu, overí jeho rozsah a kontroly."
argument-hint: "[#úloha | ABC-123] [poznámka k zmene]"
disable-model-invocation: true
allowed-tools:
  - 'Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/check.sh" *)'
  - 'Bash(git branch --show-current)'
  - 'Bash(git status --short)'
  - 'Bash(git diff --cached --stat)'
---

# /dev:commit — commit s jedným potvrdením

Použi projektové pravidlá pre správu, rozsah a verifikáciu. Pokiaľ projekt vlastný štýl neurčuje, použi nasledujúci postup.

Rýchly commit, jedno kolo otázok, jednoriadková message. Komunikuj po slovensky.

## Krok 1: Zber zmien

Stav pri spustení príkazu:
- vetva (číslo úlohy): !`git branch --show-current || true`
- `git status --short`:
!`git status --short || true`
- staged (`git diff --cached --stat`):
!`git diff --cached --stat || true`

Ďalej spusti paralelne:
- `git diff --staged` a `git diff`
- `git log --format=%s -10` (tvar a jazyk správ, ktoré pravidlo nepovie — nie ich dĺžka)
- pravidlo o commitoch projektu: pravidlá v `AGENTS.md`, pri staršom projekte aj riadok `Commit:` v Pravidlách `CLAUDE.md`, prípadne v `CLAUDE.local.md`; nemáš ho v kontexte → nájdi ho v týchto súboroch (Grep `Commit`)

Žiadne zmeny → oznám to jednou vetou a skonči.

Skupina = súbory tejto úlohy podľa konverzácie. Cudzie zmeny (iná session, rozrobená práca) nechaj mimo a vymenuj ich jedným riadkom.

## Krok 2: Číslo úlohy

- Z argumentu `$ARGUMENTS`, ak obsahuje `#123`, samostatné číslo alebo kľúč Jiry `ABC-123`.
- Inak z vetvy, keď je číslo zjavne číslo úlohy (`fix/85-...` → `[#85]`, `feature-123` → `[#123]`, `914` → `[#914]`) alebo kľúč Jiry (`feature/ABC-123-popis` → `ABC-123`).
- Tvar podľa štýlu správy (nižšie): `[#85]` pri prefixe úlohy, `ABC-123` pri Jire; štýl bez čísla úlohy ho nepotrebuje — nepýtaj sa naň.
- Nenájdené alebo nejasné (číslo je súčasť názvu: `php84-upgrade`, `redesign_2026`; vetva má iný druh čísla, než štýl čaká) → spýtaj sa **v kroku 4 spolu** s návrhom, nie v samostatnom kole.

## Krok 3: Kontrola (pred návrhom)

Pri nastavenom `commitGate.nativeHook` over účinný stav cez `bash "${CLAUDE_PLUGIN_ROOT}/scripts/init-commit-hook.sh" "${CLAUDE_PROJECT_DIR}"`. Ak pre bežný commit oznámi vykonanie v Gite, v návrhu uveď „projektová kontrola čaká na Git hook“. Pri samostatnom `git commit -m` alebo `-F` nad pripraveným indexom zhodným s pracovným stromom nechaj tento krok vykonať Git a úspech uveď až po jeho skončení. Ostatné projektové kontroly vykonaj v určenej fáze. Ak overuje kit, použi nasledujúci postup vrátane kontroly indexu v kroku 5.

- Najprv zisti, z ktorého diffu vyberá súbory projektový príkaz. Pre povinný výber z nepripravených zmien použi `--before-stage` pred `git add` a výsledok viaž na budúci obsah commitu. Pri nových cestách založ dôkaz na aktuálnom výbere natívnej kontroly alebo na konkrétnej projektovej výnimke. Pri príkaze nad stagingom over presný index pripravovaného commitu. Ak krok číta index a skupina ešte nie je pripravená, v návrhu uveď „čaká na staging“ a príslušnú kontrolu vykonaj po schválení v kroku 5. Pri viacerých commitoch over každú skupinu na jej aktuálnom HEAD.
- Použi výber pred commitom zo spoločného `dev-kit-workflow`, pri PHP projekte jeho referenciu `references/php.md`. Najprv zisti, čo projektový harness vykoná. V projektom určenej fáze raz spusti povinné kroky a vybrané testy podľa dopadu zmeny. Krok pripojený ako `required` môžeš pokryť priamo kitovým behom nižšie. Ich zlyhanie alebo zablokovanie zastaví commit. Bez konfigurácie kitu použi ich výsledok a pokračuj krokom 4. Nasledujúce pravidlá sa týkajú len dodatočnej kitovej kontroly.
- Ak projekt vyžaduje predcommitovú kontrolu aj pri dokumentácii, vykonaj ju cez jeho harness, aj keď ju konfigurácia kitu neobsahuje. Nasledujúca výnimka sa vzťahuje iba na voliteľnú kontrolu kitu. Skupina bez kódu (žiadna prípona z `commitGate.ext` v `.claude/devkit.json`; bez neho prípony z kľúčov `lint` a z `check.steps[].ext`) → kontrolu preskoč: `kontrola: netreba (len dokumentácia)`.
- Ak v tejto session posledný beh `check.sh` (`--auto` alebo `--full`) nad touto skupinou skončil PASS a odvtedy sa nič nezmenilo, neopakuj ho; commit gate obsah overí sám.
- Inak spusti (Bash timeout 600000 ms):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/check.sh" --auto --project "${CLAUDE_PROJECT_DIR}" --files <súbory skupiny>
```

- Skupina zahŕňa aj zmazané súbory. `--files` vynechaj, len keď skupina = všetky zmenené súbory.
- `0` PASS → pokračuj; do návrhu daj riadok verdiktu. Ak po kontrole zmeníš kód, kontrolu zopakuj.
- `1` FAIL v súbore skupiny → commit nenavrhuj. Ukáž nálezy `súbor:riadok — chyba` a skonči otázkou, či opraviť.
- `1` FAIL kroku nad celým projektom (unit, phpstan) len na cudzom kóde → nálezy označ `mimo commitu` a povedz, že commit gate potrebuje PASS, takže commit zatiaľ neprejde; skonči otázkou, ako postupovať.
- `3` pri očakávanom kitovom configu → zisti chybnú cestu alebo JSON a zastav.
- `4` neúplné overenie (`PARTIAL` alebo `SKIP`) → nahlás dôvody z riadkov `!`/`–` (kontajner nebeží, chýba nástroj) a skonči; commit gate by commit kódu odmietol. Kontajnery sám nespúšťaj.

## Krok 4: Návrh + jedno potvrdenie

V JEDNEJ správe:
1. Skupina súborov, ktoré idú do commitu, a riadok `mimo:` s tým, čo ostáva necommitnuté.
2. Zdôvodnenie: jednou-dvoma vetami, prečo tieto súbory tvoria jeden commit (a prečo prípadné rozdelenie).
3. Jednoriadková commit message (pravidlá nižšie). Viac logických celkov → viac commitov, každý s vlastnou message; jedno ok platí pre všetky.
4. Výsledok kontroly (riadok z kroku 3).
5. Varovanie, ak je v zmenách súbor so secrets (`.env`, `config.local.*`, credentials, `*.pem`, `*.key`) — taký súbor do skupiny nedávaj.
6. Uveď existujúce staged zmeny mimo úlohy. Zachovaj ich obsah a stav.
7. Chýbajúce číslo úlohy → otázka tu.
8. Po schválení použi postup v kroku 5.

Počkaj na jedno „ok". Odpoveď s úpravou (iná message, bez súboru X) = ok s úpravou, znova sa nepýtaj. Po schválení vykonaj jej prípadné odložené kontroly pred stagingom, priprav skupinu do indexu, dokonči jej overenie a pri úspechu ju commitni — žiadne ďalšie kolá.

## Message — vždy jeden riadok

Tvar riadku určuje pravidlo o commitoch projektu (krok 1). Čo pravidlo nepovie (jazyk, zoznam typov, scope), doplň podľa posledných commitov v tom istom štýle. Bez pravidla platí `[#XX] typ: výstih` po slovensky.

| Štýl | Tvar | Číslo úlohy | Príklad |
|---|---|---|---|
| prefix úlohy (bez pravidla) | `[#XX] typ: výstih`, typ = feat/fix/refactor/chore/docs | `[#85]` z argumentu alebo vetvy | `[#85] feat: CSV WinLatin2 export v toolbari` |
| Jira | `ABC-123 výstih` | kľúč z argumentu alebo vetvy | `ABC-123 CSV export v toolbari` |
| conventional commits | `typ(scope): výstih`; scope, keď ho pravidlo alebo história má | len keď ho pravidlo alebo história má | `fix(export): kódovanie CSV vo Windows` |

- Jazyk: podľa pravidla, inak podľa histórie, bez oboch po slovensky; technické pojmy, názvy fieldov a funkcií môžu ostať v angličtine
- Jeden riadok, rozkazovací spôsob, ideálne ≤ 72 znakov
- Bez projektového pravidla ponechaj správu jednoriadkovú.
- Ak projekt vyžaduje telo, väzbu na tiket alebo atribúciu, dodrž jeho pravidlá.
- Napíš ju sám, nepýtaj ju od používateľa

## Krok 5: Commit

- Pri cudzích staged zmenách zachovaj index. Ak povinný harness číta index alebo kit vyžaduje dôkaz pre celý obsah, zastav pri konflikte s vlastnou skupinou. Izolovaný pathspec commit použi len ak projekt takto vie overiť presný obsah a hooky to povoľujú.
- Stage cez `git add` s konkrétnymi názvami súborov (nikdy `git add -A`, `git add .` ani `git commit -a`).
- Po stagingu pri aktívnom natívnom hooku z kroku 3 ponechaj jeho krok na vykonanie v Gite. Pre ostatné kroky potvrď zhodu predbežného dôkazu a spusti kontroly určené pre index z kroku 3 vrátane projektového harnessu. Ak sa index alebo HEAD od dôkazu zmenil, over nový stav. Pred commitom skontroluj `git diff --cached`. Pre kroky vykonávané pred Gitom vyžaduj výsledok pre presne tento obsah. Pri zlyhaní alebo neúplnom dôkaze zastav.
- Pre jednoriadkovú správu použi samostatný príkaz s doslovným argumentom. Správu s telom alebo zložitým citovaním zapíš do dočasného súboru mimo projektu a použi `git commit -F <súbor>`.

```bash
git commit -m 'typ: výstižná správa'
```

- Potom `git status` a ukáž hash + message (`git log --oneline -1`).

Zamietnutie od commit gate (`[dev-kit] …` v odpovedi nástroja):
- `vyžaduje /dev:check --full` → spusti `check.sh --full` s rovnakým `--project` a `--files` (timeout 600000), pri PASS commit raz zopakuj.
- obsah sa líši od posledného PASS → spusti `check.sh --auto` s rovnakým `--project` a `--files`, pri PASS commit raz zopakuj.
- secrets → hodnotu nikdy nevypisuj ani nekopíruj; nahlás `súbor:riadok` a počkaj na rozhodnutie používateľa.
- FAIL pri opakovanej kontrole → necommituj, nahlás nálezy.

## Pravidlá

- NIKDY nepushuj — push si rieši používateľ sám
- NIKDY nepouži `--no-verify` ani neobchádzaj hooky (git hooky ani commit gate kitu — žiadne `core.hooksPath`, vypínanie `commitGate` či `disabledRules`)
- NIKDY neamenduj existujúce commity, pokiaľ to používateľ výslovne nechce
- Atribúciu prevezmi z pokynov projektu a používateľa. Predvolene ju nepridávaj.
- Ak zlyhá pre-commit hook, oprav problém a sprav NOVÝ commit (neamenduj)
- NEstage-uj súbory so secrets — varuj, ak ich zbadáš
- Komunikuj po slovensky
