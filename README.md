# dev-kit

Plugin `dev` pre Claude Code. Claude si po sebe skontroluje kód (lint, testy, statickú analýzu) skôr, ako povie „hotovo“ alebo commitne, a neprepustí commit kódu, ktorý kontrolou neprešiel. Podporuje PHP Nette (Dibi alebo Doctrine), PHP Symfony a Python.

## Inštalácia

```bash
brew install jq                                   # bez jq hooky mlčia
claude plugin marketplace add xentrix161/claude-dev-kit
claude plugin install dev@dev-kit --scope user
```

Novú verziu stiahneš príkazom `claude plugin update dev@dev-kit`. Potrebuješ Claude Code 2.1.314+ (staršie nespúšťajú hook pre Bash pri nástroji Monitor, commit tak obíde commit gate) a `jq`, `docker` len pre projekty s kontajnerom.

## Prvé spustenie v projekte

Projekt bez `.claude/devkit.json` kit nechá na pokoji: hooky v ňom nič nerobia, úvodná karta session to raz za deň pripomenie. Nastavenie vytvoríš v Claude Code v koreni projektu:

1. `/dev:project-init --dry-run` ukáže plán súborov a návrh `.claude/devkit.json`. Nič nezapíše.
2. `/dev:project-init` zapíše nastavenie, rules a `CLAUDE.md` (v lokálnom režime `CLAUDE.local.md`). Súhlas pýta po fázach: plán, zápis s kontrolou, konvencie, `CLAUDE.md`; existujúci súbor zmení len so súhlasom. Pýta sa, či nastavenie ostane len tvoje (lokálny režim, `.git/info/exclude`), alebo ho commitneš pre tím (nižšie), a či skryť atribúciu Claude v commitoch a PR (predvolene sa nemení). Plány z režimu plánovania idú do `docs/plans/` (`plansDirectory`).
3. `/dev:check --full` uloží východiskový stav. Testy, ktoré padajú už teraz, zapíše init so súhlasom do `check.knownFailures` — zoznamu známych zlyhaní, ktoré commit neblokujú, kým ich niekto neopraví; inak by commit gate blokoval každý commit. Krok `audit` (`composer audit`, `pip-audit`) beží len vo `--full` a pošle zoznam balíkov projektu na Packagist alebo PyPI; init ho zaradí len so schválením plánu.

Po novej verzii kitu obnovíš skopírované šablóny príkazom `/dev:project-init --sync`. Každý kľúč `.claude/devkit.json` s príkladom popisuje [docs/devkit-json.md](docs/devkit-json.md); editor ich dopĺňa a kontroluje podľa schémy z kľúča `$schema`.

## Tímový režim

- Commitnutý `.claude/settings.json` zaregistruje marketplace `dev-kit` a zapne plugin `dev`. Každý, kto v projekte prijme dôveru priečinka, dostane ponuku inštalácie kitu — a s ním aj commit gate a Stop kontrolu. Kto ich v projekte nechce, vypne si kit v `.claude/settings.local.json` (Keď hook otravuje).
- Hooky spúšťajú príkazy z `.claude/devkit.json` (lint, kroky kontroly) tak, ako sú zapísané. Keď ho niekto zmení a ty si ho stiahneš `git pull`, úvodná karta a prvý edit alebo commit v session na to upozornia aj s novými príkazmi. Kit ich nezablokuje, zmenu skontroluj sám.
- `docs/handoff.md` (stav práce z `/dev:handoff`) je osobný: init ho v tímovom režime dá do `.git/info/exclude`, do gitu nejde. Plány v `docs/plans/` sa commitujú s prvou zmenou úlohy.
- V lokálnom režime z kitu nič nejde do gitu a kolegov sa nič netýka.

## Čo robí sám

| Kedy | Čo sa stane |
|---|---|
| po každom edite | Lint a guardy na debug výpis (aj `console.log`), `die()`, `{!$var}`, `@`, SQL skladané reťazcom a priradenie do `innerHTML`. Pridané riadky prehľadá aj na tajomstvá. Claude nález opraví hneď. |
| na konci ťahu | Testy a analýza nad kódom, ktorý Claude v session zmenil (aj cez Bash, napr. `sed` či `git checkout`); súbory, ktoré kontrolujú len kroky `/dev:check` (napr. `.js`, `.css`), ich nespustia. Kým padajú, Claude nemôže skončiť; rovnaké zlyhanie zablokuje koniec ťahu najviac 2×, pri treťom už len upozorní. |
| pred commitom | Commit, ktorý spúšťa Claude, prejde len s PASS z `/dev:check` pre presne ten obsah. Tajomstvá a lokálne configy (`config.local.neon`, `.env`) neprejdú. Commit z terminálu alebo IDE gate nestráži — hooky vidia len príkazy Clauda. |
| pred editom | Súbory zo `secrets.forbidFiles` (lokálne configy, `.env`) Claude needituje. Pred zmenou už commitnutej migrácie sa Claude spýta. Počas `/dev:fix` je test zamknutý, takže Claude opraví kód, nie test; zmenu testu cez Bash kontrola hlási ako FAIL. |
| pri štarte session | Karta so stackom, stavom kontajnera, gitom, posledným handoffom a zmenou `devkit.json` od poslednej session. Šablóny skopírované zo staršej verzie kitu pripomenie raz za session (`/dev:project-init --sync`). |
| pred kompakciou | Do pokynov súhrnu pridá stav session: súbory, ktoré Claude menil, výsledok poslednej Stop kontroly a posledný PASS z `/dev:check`, zamknutý test a posledný handoff. Kompakciu nikdy nezastaví. |

Nebežiaci kontajner ani chýbajúci nástroj nič nezablokujú, kontrola sa len preskočí. Výsledok je potom **PARTIAL**: nič nepadlo, ale niektorý krok sa nedal spustiť, takže kód nie je overený — PARTIAL nie je PASS a commit gate commit kódu odmietne. Hláška vypíše kroky, ktoré neprebehli, a ponúkne únik: odstrániť príčinu (napríklad spustiť kontajner), alebo navrhnúť ti dočasné vypnutie cez `disabledRules` krokov, ktoré sa nedali spustiť — a keď neprebehol žiadny krok, celého `commitGate` (kontrola tajomstiev beží ďalej). Config Claude sám nemení.

## Príkazy

| Príkaz | Na čo |
|---|---|
| `/dev:check [--quick · --full · --auto] [--files …]` | kontroly projektu; PASS odomkne commit |
| `/dev:commit` | kontrola, zoskupenie zmien a jednoriadková správa podľa pravidla o commitoch v `CLAUDE.md` projektu (bez neho `[#XX] typ: výstih`); nikdy nerobí push |
| `/dev:review [branch [base]] [--security]` | review diffu: bugy, bezpečnosť, súlad s plánom, zastarané `CLAUDE.md` |
| `/dev:mr [base]` | popis PR/MR vetvy (Čo, Prečo, Ako overiť, Riziká, Po nasadení) z diffu, plánu, posledného `/dev:check` a migrácií, s review agentmi; PR/MR cez `gh` či `glab` vytvorí len so súhlasom, push nikdy |
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

Review — ktorý príkaz kedy:

- `/dev:review` — vlastná zmena pred commitom alebo MR: bugy a bezpečnosť s checklistom Nette, Symfony alebo Python, súlad s plánom v `docs/plans/`, zastarané `CLAUDE.md` a rules; drží `REVIEW.md` projektu (čo hlásiť, čo nie). `--security` pridá hĺbkový bezpečnostný prechod.
- `/code-review` (vstavaný v Claude Code) — keď chceš zvoliť hĺbku (`low` … `max`), review PR podľa čísla alebo nálezy ako komentáre do PR (`--comment`).
- `/security-review` (vstavaný) — samostatný bezpečnostný audit zmien celej vetvy, napríklad pred MR.

`/dev:debug` a `/dev:test` overia zmenu aj priamo v prehliadači (konzola, sieť, formuláre), keď je zapnutý Claude in Chrome — `claude --chrome` alebo `/chrome` ([návod](https://code.claude.com/docs/en/chrome)).

Referenčné skilly (MySQL, E2E, prístupnosť, Python, dopad zmeny, TLDR do tasku) a read-only agenti (tiché zlyhania, pokrytie testami, výkon, prístupnosť) sa načítajú samy, keď sa hodia. Skilly na dizajn systém, API, SEO a štýl legacy kódu skopíruje `/dev:project-init` do projektu len na požiadanie.

## Keď hook otravuje

- `/dev:stats` ukáže najhlučnejšie pravidlá.
- Pravidlo v projekte vypneš cez `"disabledRules": ["guard:sql-concat"]` v `.claude/devkit.json`. Id je v hláške hooku (`guard:<id>`, `lint:<ext>`, `step:<id>`, `pair:<id>`, `secrets`, `migrations`, `testLock`, `stopCheck`, `commitGate`, `testRemoved`).
- Kontrolu na konci ťahu alebo commit gate vypneš cez `"stopCheck": false` alebo `"commitGate": {"enabled": false}`. Ostatné kľúče a kedy ich použiť: [docs/devkit-json.md](docs/devkit-json.md).
- Kit v jednom projekte vypneš cez `"enabledPlugins": {"dev@dev-kit": false}` v `.claude/settings.local.json`, všade príkazom `claude plugin disable dev@dev-kit`.
- Falošný poplach nahlás ako issue: id pravidla, `súbor:riadok` a prečo nejde o chybu.

Logy sú v `~/.claude/dev-kit/`, iné miesto nastavíš cez `DEVKIT_DATA`. Úvodná karta ich pri štarte session udržiava: log rozhodnutí nad 10 MB presunie do `decisions.jsonl.1` a dáta projektu či worktree, ktorý už neexistuje, zmaže po 90 dňoch bez zmeny.

## CI projektu

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

Pracovná kópia, `make check`, CI kitu, eval suite, údržba a vydanie: [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## Licencia

MIT, pozri `LICENSE`. Časť obsahu je prevzatá z [ECC](https://github.com/affaan-m/ECC) pod MIT: zoznam je v `plugins/dev/PROVENANCE.md`, licencia v `plugins/dev/LICENSES/ECC-MIT.txt`.
