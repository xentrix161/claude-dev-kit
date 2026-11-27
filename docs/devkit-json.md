# `.claude/devkit.json` — referencia

Nastavenie pluginu `dev` v projekte. Bez tohto súboru hooky kitu v projekte nič nerobia. Vytvorí ho `/dev:project-init` zo šablóny stacku, ďalej ho upravuješ ručne. Presné správanie a hlášky popisuje kontrakt `docs/SPEC.md` §3; tento súbor je prehľad pre ľudí.

- Hooky čítajú súbor pri každom behu, zmena platí hneď.
- Príkazy z `lint` a `check.steps` sa spúšťajú tak, ako sú zapísané. Zmenu súboru (napríklad po `git pull`) ohlási úvodná karta a prvý edit alebo commit v session, nezablokuje ju.
- Neznáme kľúče a kľúče začínajúce `_` (poznámky šablóny, napríklad `_init`) skripty ignorujú. Preklep v názve kľúča preto nič nehlási — odhalí ho editor so schémou.
- Regexy (`pattern`, `secrets.patterns`, `knownFailures`) sú POSIX ERE ako v `grep -E`; `(?i)` na začiatku vypne rozlišovanie veľkosti písmen. `\s` a `\w` len mimo `[...]`, v zátvorkách `[:space:]` a `[:alnum:]_` (BSD grep na macOS). V JSON každú `\` zdvoj.
- Globy (`fullWhen`, `when`, `unless`, `forbidFiles`, `migrations.paths`) sú relatívne ku koreňu projektu: `*` = znaky okrem `/`, `**/` = žiadny alebo viac adresárov, `/**` na konci = všetko pod adresárom.

## Schéma pre editor — `$schema`

```json
"$schema": "https://raw.githubusercontent.com/xentrix161/claude-dev-kit/main/plugins/dev/devkit.schema.json"
```

Editor (VS Code, PhpStorm) podľa nej dopĺňa kľúče a hlási neznámy kľúč, zlý typ či hodnotu mimo zoznamu (`modes`, `runtime`, `changedLinesOnly`, id v `disabledRules`). Šablóny ju majú, starší projekt ju dostane cez `/dev:project-init --sync`. Schéma je z vetvy `main`, takže môže byť o krok pred nainštalovanou verziou kitu. Skripty kitu kľúč ignorujú.

## Základ

| Kľúč | Hodnota | Význam |
|---|---|---|
| `version` | `1` | verzia formátu; povinný |
| `stack` | `php-nette`, `php-symfony`, `python` | povinný; podľa neho sa vetvia príkazy `/dev:*` a úvodná karta |
| `container` | meno kontajnera alebo `""` | kde bežia lint a kroky kontroly |
| `appRoot` | cesta v kontajneri | kam kontajner mountuje koreň repa |
| `handoffDoc` | cesta, napr. `docs/handoff.md` | kam `/dev:handoff` pripisuje stav práce; úvodná karta ukáže posledný záznam |

### `container` a `appRoot`

- Prázdny alebo chýbajúci `container`: lint aj kroky bežia na hostiteľovi z koreňa projektu (`sh -c "<príkaz>"`), `appRoot` sa nepoužije.
- Nastavený `container`: príkaz beží cez `docker exec -i -w <appRoot>/<cesta projektu v repe> <container> sh -c "<príkaz>"`. Kontajner musí mountovať koreň hlavného checkoutu do `appRoot`; worktree mimo mountu krok preskočí (`worktree mimo mountu kontajnera`).
- Nebežiaci kontajner nič neblokuje: lint po edite sa ticho preskočí, krok kontroly skončí `! <id>: kontajner <c> nebeží` a kontrola PARTIAL (pozri nižšie).
- Jeden krok či lint na hostiteľovi aj pri nastavenom kontajneri: `"runtime": "host"`.
- CI bez kontajnera projektu: kópia configu s `"container": ""` cez `check.sh --config` (README, sekcia CI projektu).

## Kroky kontroly — `check`

`/dev:check`, Stop kontrola na konci ťahu aj commit gate spúšťajú tie isté kroky cez `check.sh`.

```json
"check": {
  "steps": [
    {"id": "phpstan", "requires": "vendor/bin/phpstan",
     "run": "php vendor/bin/phpstan analyse --no-progress --error-format=raw",
     "runFiles": "php vendor/bin/phpstan analyse --no-progress --error-format=raw {files}",
     "ext": [".php"], "modes": ["stop", "quick", "full"], "changedLinesOnly": "stop"},
    {"id": "unit", "requires": "vendor/bin/phpunit", "run": "php vendor/bin/phpunit --testsuite unit",
     "modes": ["stop", "quick", "full"]},
    {"id": "integration", "requires": "vendor/bin/phpunit", "run": "php vendor/bin/phpunit --testsuite integration",
     "modes": ["full"], "timeoutSec": 1800}
  ],
  "fullWhen": ["app/models/**", "db/**"],
  "knownFailures": [{"step": "integration", "pattern": "^Tests\\\\Integration\\\\OrderTest::testFlaky$"}]
}
```

| Pole kroku | Význam |
|---|---|
| `phase` | Fáza povinného kroku. `staged` je predvolená. Pre príkaz nad nepripraveným diffom zvoľ `before-stage`. |
| `newPathsReport` | Relatívna cesta k projektovému JSON s výberom nových súborov z aktuálneho kroku `before-stage`. Formát uvádzame nižšie. |
| `output` | Predvolené `log` zapíše príkaz a výstup do logu. Pri `status` kit zahodí stdout a stderr pred spracovaním vo všetkých režimoch vrátane Stop. Zostávajú metadáta behu, cesty a stav kroku. Zlyhanie posúdi podľa exit kódu, filtre výstupu sa neuplatnia. |
| `required` | Povinný celý príkaz v zvolených režimoch. Predvolená hodnota je `false`. |
| `id` | meno kroku vo výstupe a v `disabledRules` (`step:<id>`) |
| `run` | príkaz nad celým projektom |
| `runFiles` | príkaz nad zmenenými súbormi; `{files}` nahradí ich zoznam (v apostrofoch, pri dlhom zozname po dávkach) |
| `ext` | prípony súborov kroku, napr. `[".php"]`; filtrujú `{files}` a patria medzi kódové prípony commit gate |
| `modes` | kedy krok beží: `stop` (koniec ťahu), `quick` (`/dev:check`, predvolený), `full` (`/dev:check --full`); bez poľa `quick` a `full` |
| `requires` | cesta na hostiteľovi relatívne k projektu; chýbajúci predpoklad dá pri voliteľnom kroku SKIP, pri povinnom PARTIAL |
| `runtime` | `host` = vždy na hostiteľovi; `container` alebo bez poľa = v kontajneri, keď je `container` nastavený |
| `changedLinesOnly` | `true` = nálezy len na pridaných riadkoch v každom režime; `"stop"` = len v Stop kontrole (`/dev:check` ukáže aj staré nálezy súboru); `false` alebo bez poľa = všetky |
| `timeoutSec` | limit jedného behu v sekundách, predvolene 300, `0` = bez limitu; po prekročení `! krok <id> prekročil <N> s` |

Krok musí mať `run` alebo `runFiles`. Ktorý príkaz beží:

- `/dev:check` bez `--files`: `run`, ak ho krok má; inak `runFiles` nad zmenenými súbormi s príponou z `ext`.
- `--files` (tak kontroluje `/dev:commit` svoju skupinu súborov): krok s `runFiles` kontroluje len tieto súbory, aj keď má `run`.
- Stop: `runFiles`, keď sú zmenené súbory s jeho príponou, inak `run`; krok bez `ext` (testy) vždy `run`.
- Krok len s `runFiles` bez zmeneného súboru svojej prípony sa preskočí (`– <id>: žiadne zmenené súbory`).

Výsledok kontroly:

- **PASS** — aspoň jeden krok prešiel, žiadny nepadol a žiadny nemal riadok `!`; odomkne commit práve tohto obsahu.
- **FAIL** — niektorý krok našiel chybu.
- **PARTIAL** — nič nepadlo, ale krok, ktorý mal bežať, sa nedal spustiť (riadok `!`: kontajner nebeží, príkaz sa nedá spustiť, prekročený `timeoutSec`). Kód nie je overený, commit gate ho nepustí.
- **SKIP** — nebežal žiadny krok (riadky `–` len hovoria, že sa krok netýka). Ani SKIP nie je PASS.

Do `stop` patria len rýchle kroky: Stop hook má na všetky kroky spolu 600 s. Pomalé testy daj do `full` s vyšším `timeoutSec` (šablóny 1800).

### Nové súbory pred stagingom

Pri zmenách existujúcich súborov stačí bežný postup `before-stage`. Pri pridávaní ciest musí projektový krok doložiť, ktoré naozaj overil. Nastav napríklad `"newPathsReport": ".reports/php-check.json"`. Použi projektom povolený, gitom ignorovaný výstup dostupný z pracovného stromu aj po skončení príkazu v kontajneri. Kit pre tento krok poskytne v jeho runtime jedinečný `DEVKIT_SCOPE_RUN`. Wrapper zachová pôvodný návratový kód a zapíše jeden objekt JSON zo skutočného výsledku kontroly.

```json
{"run":"<hodnota DEVKIT_SCOPE_RUN>","checked":["src/New.php"],"excluded":{"README.txt":"Podľa pravidiel projektu tento krok overuje iba PHP"}}
```

Cesty sú relatívne ku koreňu. `excluded` je voliteľné. Dôvody výnimiek pochádzajú z pravidiel projektu. Starý report alebo vynechaná nová cesta bez zdôvodnenia pri úspešnom exit kóde znamenajú `PARTIAL`. Ak natívny harness ponúka úplnú sadu nad pripraveným obsahom, možno použiť tento projektový vstup vo fáze `staged`.

### Povinný projektový krok

Pri PHPStan zachovaj celý príkaz vrátane levelu, konfigurácie a cieľov. Projektový wrapper spúšťaný z koreňa na hostiteľovi dostane `runtime: host` aj v projekte s kontajnerom.

Keď výslovne pripájaš natívnu kontrolu ku kitovým krokom, nastav `"required": true`, celý príkaz v `run` a urči `modes`. Napríklad `{"id":"project","run":"make verify","requires":"Makefile","required":true,"modes":["quick","full"]}`. Rozsah určí projektový príkaz aj pri použití `--files`. Chýbajúci predpoklad alebo vypnutý krok dá PARTIAL. Nálezy sa nefiltrujú podľa zmenených riadkov ani podľa `knownFailures`. Commit s povinnými krokmi potrebuje výsledok pre rovnakú konfiguráciu, HEAD a overený obsah projektu vrátane nových súborov mimo ignore. Pre príkaz nad nepripraveným diffom nastav `phase: before-stage` a spusti `check.sh --auto --before-stage` s čistým indexom. Potom priprav presný obsah commitu a spusti `check.sh --auto`. Kit spojí výsledky podľa HEAD, konfigurácie, obsahu a skutočne úspešných krokov. Režim `full` zahŕňa povinné kontroly z `quick`. Obsah indexu aj pracovný strom sa porovnávajú pred behom, po ňom a s predmetom commitu. Zmena stagingu pri rovnakých súboroch môže zmeniť výber natívneho harnessu. Pri cudzích rozpracovaných zmenách over samostatný worktree. Pri zloženom príkaze s neistým výsledným indexom vykonaj stage samostatne. Ignorované dáta, služby a runtime overuje natívny harness. So začiatkom každej riadnej kontroly prestane platiť predošlý PASS. Starší súbežný beh oznámi, že rozhoduje novší, a pri vlastnom úspechu vráti `PARTIAL` s kódom 4. Pre MR platí log vybraného behu aj po neskoršej kontrole s alternatívnym configom. Príznak je predvolene vypnutý pre kompatibilitu s existujúcimi voliteľnými krokmi.

### `fullWhen`

Globy jadra projektu (modely, doménová logika, migrácie). Zmena súboru, ktorý na ne sedí, prepne `/dev:check --auto` na `full` a commit gate pýta PASS z `/dev:check --full`, nie z rýchlej kontroly.

### `knownFailures`

Staré padajúce testy, ktoré nemajú blokovať commit, kým ich niekto neopraví. `/dev:project-init` ich zapíše len so súhlasom.

- Kit rozozná len identifikátory: PHPUnit `N) Trieda::metóda`, pytest `FAILED <id>` a `ERROR <id>`, Nette Tester `-- FAILED: <cesta>` a záznamy `composer audit` (Advisory ID, CVE) či `pip-audit` (ID a aliasy).
- `step` = `id` kroku, `pattern` = ERE na jeden identifikátor; ukotvi ho `^…$` a escapuj metaznaky (`\\.`, `\\\\` v JSON).
- Keď krok padne a každý nájdený identifikátor sedí na vzor jeho kroku, krok nepadá: riadok dostane `známe zlyhania: N` a súhrn ho počíta ako `známe`. Nové zlyhanie popri známych je FAIL.
- Statická analýza a lintery (phpstan, phpcs, mypy) identifikátory nemajú — na ne baseline nástroja alebo `changedLinesOnly`.

## Lint po edite — `lint`, `lintChangedLinesOnly`

```json
"lint": {
  ".php": ["php -l {file}", {"run": "php vendor/bin/phpcs -q -n --report=emacs {file}", "runtime": "host"}],
  ".latte": "php vendor/bin/latte-lint {file}"
},
"lintChangedLinesOnly": true
```

- Kľúč je prípona s bodkou; hodnota príkaz, objekt `{"run": …, "runtime": …}` alebo ich zoznam. `{file}` = cesta upraveného súboru relatívne k projektu.
- Beží po každom Edit/Write súboru s touto príponou. Nález Claude opraví hneď; chýbajúci nástroj (`command not found`, exit 126/127) ani nebežiaci kontajner edit neblokujú.
- `lintChangedLinesOnly: true` ponechá len nálezy na pridaných riadkoch; syntaktickú chybu a pád nástroja hlási vždy.
- Prípony z `lint` sú kódové: ich zmena spustí Stop kontrolu a commit gate ich ráta, keď `commitGate.ext` chýba.
- Lint nemá vlastný limit času, ohraničí ho timeout hooku (60 s). Vypnutie jednej prípony: `lint:.php`.

## Guardy — `guards`

```json
"guards": [
  {"id": "debug-php", "ext": [".php", ".latte"], "pattern": "(^|[^>:$_[:alnum:]])(dump|dd|bdump)\\(", "message": "debug výpis v kóde"}
]
```

- Regex nad pridanými riadkami súborov s príponou z `ext` — po edite aj v Stop kontrole (tá vidí aj zmeny cez Bash). Nález: `<súbor>:<riadok> — <message> [guard:<id>]`.
- Starý kód mimo pridaných riadkov guard nehlási. Vypnutie: `guard:<id>`.

## Páry — `pairs`

```json
"pairs": [
  {"id": "validator-test", "when": "libs/Validator/**", "unless": ["tests/**"],
   "say": "Zmena validátora bez zmeny testu: navrhni používateľovi regresný test."}
]
```

- Pripomienka na konci ťahu, raz za session: Claude zmenil súbor zo `when` a žiadny zmenený súbor (ani commitnutý v tejto session) nesedí na `unless` → Claude dostane text `say`.
- `when` a `unless` sú glob alebo zoznam globov. Pár nič neblokuje. Vypnutie: `pair:<id>`.

## Tajomstvá — `secrets`

```json
"secrets": {
  "patterns": ["\\b[0-9a-f]{50}\\b"],
  "allow": ["tests/fixtures/"],
  "forbidFiles": ["app/config/config.local.neon", "**/.env"]
}
```

- `patterns` dopĺňajú predvolené vzory kitu (heslo či token priradený v kóde, súkromný kľúč, `AKIA…`, priradenie do premennej `…TEST_PASSWORD`). Pridané riadky sa kontrolujú po edite a pred commitom; nález s tajomstvom commit zamietne a hodnota sa nikde nevypíše celá.
- `allow`: cesty bez kontroly tajomstiev; položka s `/` na konci je prefix, inak glob.
- `forbidFiles`: súbory, ktoré Claude neupraví (Edit/Write) ani necommitne; čítať ich môže. Zhoda bez ohľadu na veľkosť písmen.
- Vypnutie: `secrets` (vzory aj `forbidFiles` naraz).

## Migrácie — `migrations`

```json
"migrations": {"paths": ["db/migrations/**"]}
```

Pred úpravou súboru, ktorý sedí na glob a už je v `HEAD`, sa Claude spýta — aplikovaná migrácia sa neupravuje, patrí sa vytvoriť novú. Nová necommitnutá migrácia prejde ticho. Vypnutie: `migrations`.

## Zámok testu — `testLock`

```json
"testLock": {"ttlHours": 6}
```

`/dev:fix` zamkne repro test, aby Claude opravil kód, nie test: Edit/Write testu sa zamietne a zmena cez Bash dá kontrole FAIL. `ttlHours` je platnosť zámku v hodinách (predvolene 6). Odomknutie: `/dev:fix --unlock`. Vypnutie: `testLock`.

## Stop kontrola — `stopCheck`

- `true` (predvolene): keď Claude v ťahu zmenil kód (prípona z `lint` alebo z `ext` kroku s režimom `stop`), na konci ťahu bežia kroky `stop` a guardy. Kým padajú, Claude nemôže skončiť; to isté zlyhanie zablokuje koniec ťahu najviac 2×, potom už len upozorní. PARTIAL neblokuje.
- `false` vypne celý Stop hook vrátane pripomienok párov a zmazaných testov. Rovnako `disabledRules: ["stopCheck"]`.

## Commit gate — `commitGate`

```json
"commitGate": {"enabled": true, "ext": [".php", ".latte", ".neon", ".twig"]}
```

- Claude s aktívnym pluginom a Codex s potvrdeným osobným hookom overujú shellový commit. Pri vlastnom commite v termináli alebo IDE rozhodujú Git hooky projektu.
- Pri voliteľných krokoch rozhoduje prípona z `ext` (predvolene z `lint` a krokov). Pri povinných krokoch sa overuje obsah, HEAD a konfigurácia aj pri dokumentácii, prázdnom commite alebo úprave správy. PARTIAL vyžaduje doplnenie chýbajúceho výsledku.
- `enabled: false` vypne gate; kontrola tajomstiev pred commitom beží ďalej. Rovnako `disabledRules: ["commitGate"]`.

Voliteľný `nativeHook` je cesta k verzovanému spustiteľnému súboru pre-commit od koreňa projektu. Použi ho, keď tento skript pokrýva celú povinnú kontrolu a funguje samostatne nad indexom z koreňa. Príklad spoločného nastavenia:

```json
{
  "commitGate": {"enabled": true, "nativeHook": ".githooks/pre-commit"},
  "check": {"steps": [{"id": "project", "runtime": "host", "required": true, "run": "./.githooks/pre-commit", "modes": ["quick", "full"]}]}
}
```

Git musí v tomto checkoute používať ten istý súbor v nezmenenom stave oproti HEAD aj indexu. Pri samostatnom commite celého pripraveného indexu zhodného s pracovným stromom potom kontrolu vykoná Git. Cudzie rozpracované zmeny zachovaj a over v samostatnom worktree. Pri chýbajúcej aktivácii, inom hooku, ďalších krokoch quick/full, aktívnom zámku testu alebo režime `output: status` kit vyžaduje vlastný výsledok. Pri čiastočnom pokrytí môže Git svoj krok opakovať. Init ukáže aktuálny stav. Pokrytie MR dokladá samostatný výsledok pre jeho rozsah.

## Vypnutie pravidiel — `disabledRules`

```json
"disabledRules": ["guard:sql-concat", "step:integration"]
```

| Id | Vypne |
|---|---|
| `guard:<id>` | jeden guard |
| `lint:<prípona>` | lint jednej prípony, napr. `lint:.latte` |
| `step:<id>` | krok kontroly vo všetkých režimoch |
| `pair:<id>` | pripomienku páru |
| `secrets` | kontrolu tajomstiev po edite aj pred commitom a `forbidFiles` |
| `migrations` | otázku pred úpravou commitnutej migrácie |
| `testLock` | zámok testu |
| `stopCheck` | Stop kontrolu |
| `commitGate` | commit gate |
| `testRemoved` | pripomienku zmazaného testu |

Id pravidla je v každej hláške hooku, najhlučnejšie pravidlá ukáže `/dev:stats`. Zákaz zápisu pre agentov kitu vypnúť nejde.

## Kedy čo použiť

| Chcem | Kľúč |
|---|---|
| projekt bez Dockeru | `"container": ""` |
| nástroj na hostiteľovi pri projekte v kontajneri (Node) | `"runtime": "host"` v kroku či lint príkaze |
| statickú analýzu len nad zmenenými súbormi bez starých nálezov pri Stop | `runFiles` a `"changedLinesOnly": "stop"` |
| pomalé testy len pred commitom jadra | krok s `"modes": ["full"]`, `timeoutSec` a `fullWhen` |
| staré padajúce testy neblokujú commit | `knownFailures` |
| hlučný guard alebo krok, ktorý v projekte nedáva zmysel | `disabledRules` |
| Claude nesmie upraviť lokálny config | `secrets.forbidFiles` |
