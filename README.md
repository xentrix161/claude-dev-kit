# dev-kit

Plugin `dev` pre Claude Code. Claude si po sebe skontroluje kód (lint, testy, statickú analýzu) skôr, ako povie „hotovo“ alebo commitne. Podporuje PHP Nette (Dibi alebo Doctrine), PHP Symfony a Python.

## Inštalácia

```bash
brew install jq                                   # bez jq hooky mlčia
claude plugin marketplace add xentrix161/claude-dev-kit
claude plugin install dev@dev-kit --scope user
```

Novú verziu stiahneš príkazom `claude plugin update dev@dev-kit`. Potrebuješ Claude Code 2.1.314+ (staršie nespúšťajú hook pre Bash pri nástroji Monitor, commit tak obíde commit gate) a `jq`, `docker` len pre projekty s kontajnerom.

## Zapnutie v projekte

Projekt bez `.claude/devkit.json` kit nechá na pokoji: hooky v ňom nič nerobia. Nastavenie vytvoríš takto:

1. `/dev:project-init --dry-run` ukáže plán súborov a návrh `.claude/devkit.json`. Nič nezapíše.
2. `/dev:project-init` zapíše nastavenie, rules a `CLAUDE.md` (v lokálnom režime `CLAUDE.local.md`). Súhlas pýta po fázach: plán, zápis s kontrolou, konvencie, `CLAUDE.md`; existujúci súbor zmení len so súhlasom. Nastavenie môže ostať lokálne (`.git/info/exclude`) alebo ho commitneš pre tím. V tímovom režime `.claude/settings.json` zaregistruje marketplace `dev-kit` a zapne plugin `dev`, takže kolega ho dostane po prijatí dôvery priečinka. Plány z režimu plánovania idú do `docs/plans/` (`plansDirectory`); skrytie atribúcie Claude v commitoch a PR je otázka initu, predvolene sa nemení.
3. `/dev:check --full` uloží východiskový stav. Staré zlyhania sa zapíšu do `check.knownFailures` len so súhlasom, inak by commit gate blokoval každý commit. Krok `audit` (`composer audit`, `pip-audit`) beží len vo `--full` a pošle zoznam balíkov projektu na Packagist alebo PyPI; init ho zaradí len so schválením plánu.

Po novej verzii kitu obnovíš skopírované šablóny príkazom `/dev:project-init --sync`.

Hooky spúšťajú príkazy z `.claude/devkit.json` (lint, kroky kontroly) tak, ako sú zapísané. Keď sa súbor zmení, napríklad po `git pull` v tímovom režime, úvodná karta a prvý edit alebo commit v session na to upozornia aj s novými príkazmi. Kit ich nezablokuje, zmenu skontroluj sám.

## Čo robí sám

| Kedy | Čo sa stane |
|---|---|
| po každom edite | Lint a guardy na debug výpis (aj `console.log`), `die()`, `{!$var}`, `@`, SQL skladané reťazcom a priradenie do `innerHTML`. Pridané riadky prehľadá aj na tajomstvá. Claude nález opraví hneď. |
| na konci ťahu | Testy a analýza nad kódom, ktorý Claude v session zmenil (aj cez Bash, napr. `sed` či `git checkout`); súbory, ktoré kontrolujú len kroky `/dev:check` (napr. `.js`, `.css`), ich nespustia. Kým padajú, Claude nemôže skončiť; rovnaké zlyhanie zablokuje koniec ťahu najviac 2×, pri treťom už len upozorní. |
| pred commitom | Commit prejde len s PASS z `/dev:check` pre presne ten obsah. Tajomstvá a lokálne configy (`config.local.neon`, `.env`) neprejdú. |
| pred editom | Súbory zo `secrets.forbidFiles` (lokálne configy, `.env`) Claude needituje. Pred zmenou už commitnutej migrácie sa Claude spýta. Počas `/dev:fix` je test zamknutý, takže Claude opraví kód, nie test; zmenu testu cez Bash kontrola hlási ako FAIL. |
| pri štarte session | Karta so stackom, stavom kontajnera, gitom, posledným handoffom a zmenou `devkit.json` od poslednej session. Šablóny skopírované zo staršej verzie kitu pripomenie raz za session (`/dev:project-init --sync`). |
| pred kompakciou | Do pokynov súhrnu pridá stav session: súbory, ktoré Claude menil, výsledok poslednej Stop kontroly a posledný PASS z `/dev:check`, zamknutý test a posledný handoff. Kompakciu nikdy nezastaví. |

Nebežiaci kontajner ani chýbajúci nástroj nič nezablokujú, kontrola sa len preskočí. Commit kódu bez PASS však commit gate odmietne. Po kontrole s výsledkom PARTIAL vypíše kroky, ktoré neprebehli, a ponúkne únik: odstrániť príčinu (napríklad spustiť kontajner), alebo navrhnúť používateľovi dočasné vypnutie cez `disabledRules` krokov, ktoré sa nedali spustiť — a keď neprebehol žiadny krok, celého `commitGate` (kontrola tajomstiev beží ďalej). Config Claude sám nemení.

## Príkazy

| Príkaz | Na čo |
|---|---|
| `/dev:check [--quick · --full · --auto] [--files …]` | kontroly projektu; PASS odomkne commit |
| `/dev:commit` | kontrola, zoskupenie zmien a jednoriadková správa podľa pravidla o commitoch v `CLAUDE.md` projektu (bez neho `[#XX] typ: výstih`); nikdy nerobí push |
| `/dev:review [branch [base]] [--security]` | review diffu: bugy, bezpečnosť, súlad s plánom, zastarané `CLAUDE.md` |
| `/dev:fix` | repro test → zámok testu → oprava kódu → kontrola |
| `/dev:test` | test najprv: RED → GREEN → REFACTOR (PHPUnit, Nette Tester, pytest) |
| `/dev:debug` | logy a stav prostredia → hypotéza → minimálny repro → návrh opravy |
| `/dev:plan` | plán do `docs/plans/` pre väčšie alebo rizikové úlohy |
| `/dev:handoff` | stav práce do handoff dokumentu pred `/clear` |
| `/dev:explain` | čo kód robí, z čoho závisí a čo hrozí pri zmene |
| `/dev:learn` | návrhy pravidiel do pamäte alebo `.claude/rules/`; zapíše len schválené |
| `/dev:stats` | čo hooky zachytili a ktoré pravidlá sú najhlučnejšie |
| `/dev:project-init` | nastavenie projektu zo šablóny |
| `/dev:ecc-production-audit` | audit pred nasadením (len ručne) |

Referenčné skilly (MySQL, E2E, prístupnosť, Python, dopad zmeny, TLDR do tasku) a read-only agenti (tiché zlyhania, pokrytie testami, výkon, prístupnosť) sa načítajú samy, keď sa hodia. Skilly na dizajn systém, API, SEO a štýl legacy kódu skopíruje `/dev:project-init` do projektu len na požiadanie.

## Keď hook otravuje

- `/dev:stats` ukáže najhlučnejšie pravidlá.
- Pravidlo v projekte vypneš cez `"disabledRules": ["guard:sql-concat"]` v `.claude/devkit.json`. Id je v hláške hooku (`guard:<id>`, `lint:<ext>`, `step:<id>`, `pair:<id>`, `secrets`, `migrations`, `testLock`, `stopCheck`, `commitGate`, `testRemoved`).
- Kontrolu na konci ťahu alebo commit gate vypneš cez `"stopCheck": false` alebo `"commitGate": {"enabled": false}`.
- Všetky kľúče `.claude/devkit.json` s príkladmi a s tým, kedy ktorý použiť, popisuje [docs/devkit-json.md](docs/devkit-json.md). Editor ich dopĺňa a kontroluje podľa schémy z kľúča `$schema`.
- Kit v jednom projekte vypneš cez `"enabledPlugins": {"dev@dev-kit": false}` v `.claude/settings.local.json`, všade príkazom `claude plugin disable dev@dev-kit`.
- Falošný poplach nahlás ako issue: id pravidla, `súbor:riadok` a prečo nejde o chybu.

Logy sú v `~/.claude/dev-kit/`, iné miesto nastavíš cez `DEVKIT_DATA`. Úvodná karta ich pri štarte session udržiava: log rozhodnutí nad 10 MB presunie do `decisions.jsonl.1` a dáta projektu či worktree, ktorý už neexistuje, zmaže po 90 dňoch bez zmeny.

## CI

`check.sh` beží aj v CI projektu bez Claude Code a bez inštalácie pluginu (`claude plugin marketplace add` netreba): stačí `bash`, `git`, `jq`, klon kitu a nástroje projektu (PHP s `composer install`, Python s balíkmi…), lebo kroky z `devkit.json` sa spúšťajú tak, ako sú zapísané.

```bash
bash <kit>/plugins/dev/scripts/check.sh --full --project .
```

- Exit 0 = PASS, 1 = FAIL, 3 = chyba configu alebo argumentov, 4 = PARTIAL alebo SKIP (niečo sa neoverilo). Job zlyhá pri každom inom kóde než 0.
- Runner bez kontajnera projektu dostane kópiu configu s `"container": ""` cez `--config <súbor>` alebo premennú `DEVKIT_CONFIG` a kroky pustí u seba. V kópii vypneš aj kroky, ktoré v CI nemajú prostredie (`"disabledRules": ["step:integration"]`). Projekt s lokálnym nastavením (`.git/info/exclude`) commitne pre CI vlastný súbor a odovzdá ho rovnako.
- Beh s iným configom nezapíše `pass.json`, lokálne teda commit neodomkne; povie to riadok `config:` vo výstupe.
- Čerstvý checkout nemá zmenené súbory: kroky s `run` bežia nad celým projektom, kroky len s `runFiles` (`phpcs`, `ruff`, `eslint`…) sa preskočia. Na PR im daj zmenené súbory: `--files $(git diff --name-only --diff-filter=d <báza>...HEAD)`, kde `<báza>` je `origin/$GITHUB_BASE_REF` (GitHub, checkout s `fetch-depth: 0`) alebo `$CI_MERGE_REQUEST_DIFF_BASE_SHA` (GitLab). S `--files` kontroluje krok s `runFiles` len tieto súbory, aj keď má `run` (napr. `phpstan`); kroky len s `run` bežia ďalej nad celým projektom.
- URL klonu kitu a tag vydania (`dev--v<verzia>`) drž v premenných CI `DEVKIT_REPO` a `DEVKIT_REF`. Plný log je v `DEVKIT_DATA` runnera, cestu vypíše riadok `log:`.

GitHub Actions (`.github/workflows/dev-kit.yml`, premenné v Settings → Secrets and variables → Actions → Variables):

```yaml
name: dev-kit
on: [push, pull_request]
jobs:
  check:
    runs-on: ubuntu-latest   # git aj jq sú v obraze
    steps:
      - uses: actions/checkout@v7
      # príprava nástrojov projektu (setup-php + composer install, setup-python + pip install…)
      - name: dev-kit check
        env:
          DEVKIT_REPO: ${{ vars.DEVKIT_REPO }}
          DEVKIT_REF: ${{ vars.DEVKIT_REF }}
        run: |
          git clone -q --depth 1 --branch "$DEVKIT_REF" "$DEVKIT_REPO" "$RUNNER_TEMP/dev-kit"
          jq '.container = ""' .claude/devkit.json > "$RUNNER_TEMP/devkit.json"
          DEVKIT_CONFIG="$RUNNER_TEMP/devkit.json" bash "$RUNNER_TEMP/dev-kit/plugins/dev/scripts/check.sh" --full --project .
```

GitLab CI (`.gitlab-ci.yml`, premenné v Settings → CI/CD → Variables):

```yaml
dev-kit:
  image: <obraz s nástrojmi projektu, bash, git a jq>
  script:
    - git clone -q --depth 1 --branch "$DEVKIT_REF" "$DEVKIT_REPO" /tmp/dev-kit
    - jq '.container = ""' .claude/devkit.json > /tmp/devkit.json
    - DEVKIT_CONFIG=/tmp/devkit.json bash /tmp/dev-kit/plugins/dev/scripts/check.sh --full --project .
```

## Vývoj kitu

```bash
git clone https://github.com/xentrix161/claude-dev-kit.git
claude plugin marketplace add ./claude-dev-kit    # in-place: zmena platí po /reload-plugins
make check                                        # validate --strict, guardy, selftest, rozpočet tokenov
```

- Kontrakt (názvy, cesty, výstupy, `devkit.json`): `docs/SPEC.md`. Ďalšie ciele vypíše `make help`.
- Jednorazový test bez inštalácie: `claude --plugin-dir ./claude-dev-kit/plugins/dev`.
- Skripty sú pre bash 3.2 (macOS) bez GNU-only prepínačov. Text pre ľudí je po slovensky s plnou diakritikou.
- `make details` stráži, aby trvalý kontext kitu ostal pod 3 000 tokenov. Odhad `claude plugin details` závisí od prihlásenia aj od modelu, rozpočet preto overuj v prihlásenom Claude Code.
- [CI](https://github.com/xentrix161/claude-dev-kit/actions/workflows/check.yml) (`.github/workflows/check.yml`) spustí pri pushi do `main` a pri každom PR na `ubuntu-latest` (bash 5, GNU nástroje) aj `macos-latest` (`/bin/bash` 3.2, BSD nástroje) s najnovším Claude Code z npm povinne `make validate`, `make guards` a `make selftest`, tie prihlásenie nepotrebujú. `make guards` skontroluje celý strom skriptov (`bash -n`, guardy `bash4` a `gnu-only` z `.claude/devkit.json`, `shellcheck -S warning`, ak ho runner má), nielen pridané riadky ako hooky. `make details` tam beží len informatívne (`continue-on-error`): runner nie je prihlásený a `claude plugin details` bez prihlásenia počíta iný, nižší odhad tokenov (pri tomto kite zhruba polovicu), takže rozpočet 3 000 tokenov stráži len lokálny `make check` v prihlásenom Claude Code.

### Údržba

- **Hlučné pravidlo:** oprav vzor alebo prah v šablóne kitu, pridaj prípad do `tests/selftest.sh` a v projektoch spusti `/dev:project-init --sync`.
- **Claude Code:** po `claude update` spusti `make check`. Ak novú funkciu Claude Code zvládne sám, príslušný kus kitu zruš.
- **ECC:** raz mesačne `make upstream` (karta to pripomenie po 30 dňoch, len keď plugin beží z pracovnej kópie kitu) vypíše zmenené prevzaté kusy. Zmeny preber ručne a posuň pin v `plugins/dev/PROVENANCE.md`. Klon ECC hľadá v `ECC_DIR`, predvolene `<KIT>/../ECC` (vedľa pracovnej kópie kitu).
- **Eval suite:** pred vydaním a po zmene skillov `check`, `commit`, `review` alebo `fix` spusti `make eval`. Päť prípadov v `plugins/dev/evals/` beží nad syntetickým projektom v dočasnom adresári, každý 3× s kitom a 3× bez neho, Bash v sandboxe. Každý beh agenta aj sudca `llm` graderov stojí tokeny, preto eval nie je v `make check`.
  - Tabuľka: `WITH` je skóre s kitom (cieľ 1.00), `W/OUT` ten istý prompt bez kitu, `Δ` rozdiel. Príkazy `/dev:*` bez kitu neexistujú, takže bez neho prejdú len gradery typu „niečo sa nestalo“ (žiadny push, žiadne PASS). O výsledku preto rozhoduje `WITH`; `Δ` blízko nuly znamená, že prípad netestuje kit a treba ho sprísniť.
  - Prípad pod prahom (`--threshold`, predvolene 1.0) skončí `make` chybou. Padnuté gradery s vysvetlením ukáže `plugins/dev/evals/results/<čas>/report.html`, rovnaké dáta pre skripty sú v `aggregate-result.json`.
  - Agenti aj sudca bežia na Sonnete (`EVAL_MODEL`, `EVAL_JUDGE`): predvolený model účtu býva drahší a sudca `haiku` dáva falošné FAIL pri správnej odpovedi. Lacný prvý odhad: `EVAL_ARGS="--runs 1"` (10 behov, zhruba 0,75 USD). Ďalšie voľby cez `EVAL_ARGS`, napr. ladenie jedného prípadu `EVAL_ARGS="--case check-partial --runs 1 --ablation none"` alebo súbežnosť `-j 4`. Report ostáva lokálne, keď eval spúšťa Claude Code; z terminálu sa zverejní ako súkromný artifact na claude.ai (`--no-publish` ho nechá lokálne). `EVAL_ARGS="--max-cost-usd 0"` len načíta a skontroluje súbory suite, nespustí ani jeden beh.

### Vydanie

```bash
make release VERSION=0.5.0             # poistky, verzia v plugin.json, dátum v CHANGELOG, validate --strict, tag --dry-run
git add plugins/dev/.claude-plugin/plugin.json CHANGELOG.md
git commit -m "vydanie dev 0.5.0"
git push
make tag                               # po zelenom CI: tag dev--v0.5.0 na origin
```

- `make release` zmení verziu, až keď je strom čistý, vetva je `main`, verzia je vyššia ako posledný tag `dev--v*`, `CHANGELOG.md` má sekciu `## 0.5.0 — nevydané` a prejde `make check`; inak skončí s hláškou bez zmeny súboru. Potom nahradí `— nevydané` dnešným dátumom. Keď `claude plugin validate --strict` alebo `tag --dry-run` zlyhá, `plugin.json` aj `CHANGELOG.md` vráti.
- `make tag` taguje len čistý strom, ktorého `HEAD` je po `git fetch` zhodný s `origin/main` a CI pre ten commit skončilo `success` (`gh run list`). Bežiace alebo zlyhané CI tag odmietne. Bez `gh` taguj ručne: `claude plugin tag --push plugins/dev`. GitHub Release kit nevytvára, vydanie je len tag.

Verzia je len v `plugins/dev/.claude-plugin/plugin.json`. Bez jej zvýšenia ostatní novú verziu nedostanú; inštalácia z lokálnej cesty verziu ignoruje.

## Licencia

MIT, pozri `LICENSE`. Časť obsahu je prevzatá z [ECC](https://github.com/affaan-m/ECC) pod MIT: zoznam je v `plugins/dev/PROVENANCE.md`, licencia v `plugins/dev/LICENSES/ECC-MIT.txt`.
