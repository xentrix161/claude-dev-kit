# dev-kit

Spoločný vývojový playbook pre Codex a Claude Code používa pravidlá a kontroly otvoreného projektu. Voliteľný Claude plugin `dev` pridáva hooky a šablóny pre Nette, Symfony a Python.

## Codex

Z koreňa klonu prepoj skilly, ktoré ešte nemáš v osobnom adresári Codexu.

```bash
mkdir -p ~/.agents/skills
ln -s "$PWD/plugins/dev/skills/dev-kit-workflow" ~/.agents/skills/
ln -s "$PWD/plugins/dev/skills/project-init" ~/.agents/skills/
ln -s "$PWD/codex/dev-kit" ~/.agents/skills/
```

V novom chate môžeš cez `@` vyhľadať `dev-kit-workflow`. Odkaz sleduje aktuálnu pracovnú kópiu aj po aktualizácii. Pred opakovanou inštaláciou over cieľ cez `readlink ~/.agents/skills/dev-kit-workflow`. Na pravidelné používanie stačí do osobných pokynov pridať vetu „Pri vývoji použi dev-kit-workflow a projektový harness.“ Claude načíta ten istý skill z pluginu.

V aplikácii napíš `@`, vyhľadaj `project-init` a vyber skill kitu. Môže sa zobraziť ako `dev:project-init`. V novom projekte zobrazí plán nastavenia. S `--dry-run` skončí pri náhľade. Vstavané `/init` v Codexe vytvára základ `AGENTS.md`. [Výber skillu](https://learn.chatgpt.com/docs/build-skills) · [Príkazy v aplikácii](https://learn.chatgpt.com/docs/reference/slash-commands)

Pre ďalšie príkazy vyber cez `@` skill `dev-kit` a dopíš napríklad `check --quick`, `review` či `mr`. Samotný skill vypíše ponuku. V CLI použi napríklad `$dev-kit init --dry-run` alebo `$dev-kit check --quick`. Oba príkazové skilly sa otvárajú na vyžiadanie. Automaticky používaný [vývojový postup](plugins/dev/skills/dev-kit-workflow/SKILL.md) ostáva stručný.

Automatickú kontrolu pred commitom pripoj z koreňa trvalého klonu:

```bash
bash tools/install-codex-hook.sh
```

Inštalátor pridá do osobného `hooks.json` jednu kontrolu a vypíše cestu k zálohe existujúceho súboru. V novom Codexe otvor `/hooks`, skontroluj cestu k `pre-bash.sh` a potvrď dôveru. V projekte s `.claude/devkit.json` hook pri shellovom commite overí výsledok pre pripravovaný obsah. Povinný projektový krok pripojený ku kontrole kitu tak stačí vykonať raz. Vlastný Git hook projektu sa spúšťa podľa jeho nastavenia aj pri commite z terminálu či IDE. V projekte bez konfigurácie kitu naďalej rozhodujú jeho vlastné pokyny a kontroly. [Hooky v Codexe](https://developers.openai.com/codex/hooks/)

## Existujúci projekt

Pri drobnej oprave stačí nájsť dotknuté miesto, opraviť ho a doložiť cielené overenie. Povinné kontroly určuje projekt aj vtedy, keď sa zmenil jediný riadok. Podrobnosti pre plán, review, MR a vydanie otvor až pri príslušnej úlohe.

Claude Code od verzie 2.1.277 v predvolenom režime načíta samotný `AGENTS.md`. Súbor `CLAUDE.local.md` slúži na súkromné pokyny používateľa pre konkrétny checkout. Kit ho nevytvára. Ak v projekte alebo nadradenom adresári existuje `CLAUDE.local.md` či iný projektový Claude súbor, skontroluj účinné pokyny. [Načítavanie inštrukcií Claude](https://code.claude.com/docs/en/memory#when-claude-code-reads-agentsmd)

Začni projektovým `AGENTS.md`, zdokumentovanými príkazmi a existujúcim harnessom. Tento postup funguje aj bez `.claude/devkit.json` a bez šablóny pre daný jazyk. Pri rozpore v rozsahu kontroly dolož, čo projekt skutočne spúšťa. [Fázy playbooku](plugins/dev/skills/dev-kit-workflow/references/playbook.md)

Pri `fix`, `test`, `deps` aj produkčnom audite rozhoduje výsledok povinného projektového harnessu. Pri povinnom kroku nad nepripraveným diffom nastav `phase: before-stage` a spusti `/dev:check --auto --before-stage` pred `git add`. Pripravený obsah následne over cez `/dev:check --auto`. Pri nových súboroch v tejto fáze prevezmi z harnessu skutočný výber ciest. Projekt môže povoliť iba stav kroku bez ukladania jeho výstupu. [Nastavenia kontrol](docs/devkit-json.md#nové-súbory-pred-stagingom)

Pri príprave MR kit doloží vlastný beh pre konkrétny commit. Pokrytie zmien musí potvrdiť projektový harness alebo CI. Prevádzkový postup otvor pri migrácii, monitoringu, nasadení alebo incidente. [Prevádzka](plugins/dev/skills/dev-kit-workflow/references/operations.md) · [Bezpečnostné review](plugins/dev/skills/dev-kit-workflow/references/security.md)

### Pred commitom

V PHP projekte použi jeho audit lockfile a PHPStan s predpísaným rozsahom. Vyber unit testy pre zmenenú logiku, integračné testy pre dotknuté rozhrania a E2E pre dotknuté používateľské toky. Výsledok existujúceho harnessu môže pokryť viac krokov naraz. Nové PHP šablóny vedia audit a PHPStan pripojiť ako povinné kroky. Príkazy E2E, rozsah integračných sád a prostredie určuje projekt. Pri chýbajúcej povinnej kontrole commit počká. [PHP](plugins/dev/skills/dev-kit-workflow/references/php.md) · [JS a UI](plugins/dev/skills/dev-kit-workflow/references/js.md) · [Prevádzka](plugins/dev/skills/dev-kit-workflow/references/operations.md)

## Inštalácia pre Claude Code

```bash
brew install jq                                   # bez jq hooky mlčia
claude plugin marketplace add xentrix161/claude-dev-kit
claude plugin install dev@dev-kit --scope user
```

Novú verziu stiahneš príkazom `claude plugin update dev@dev-kit`. Potrebuješ Claude Code 2.1.314+ (staršie nespúšťajú hook pre Bash pri nástroji Monitor, commit tak obíde commit gate) a `jq`, `docker` len pre projekty s kontajnerom.

## Prvé spustenie v projekte

Projekt bez `.claude/devkit.json` kit nechá na pokoji: hooky v ňom nič nerobia, úvodná karta session to raz za deň pripomenie. V koreni projektu spusti onboarding podľa toho, čo chceš pripojiť.

1. V Codexe vyber cez `@` **project-init**, v Claude spusti `/dev:project-init`. Init ukáže plán vrátane kontroly pred commitom. Uvidíš, ktoré projektové príkazy ju zabezpečia. Pre verzovaný pre-commit, ktorý pokrýva celý povinný krok, môže tím zdieľať rovnaký skript ako kontrolu kitu. V checkoute s aktívnym hookom ho vykoná Git. V čerstvom klone bez aktívneho hooku si Codex či Claude pred commitom vyžiada úspešný výsledok rovnakého skriptu.
2. Vyber a schváľ variant **iba pre mňa** alebo **pre tím**. Vybraný plán zahŕňa aj nastavenie hooku. Lokálny variant používa osobné nastavenia checkoutu. Tímový variant pripraví zdieľané súbory vrátane prípadného doplnenia `AGENTS.md`. Pri odmietnutí aj pri `--dry-run` zostane projekt bez zápisu. Opakovaný init v nastavenom projekte ukáže stav a možnosť synchronizácie.
3. `/dev:check --full` uloží východiskový stav. Pri voliteľných kitových krokoch testy, ktoré padajú už teraz, zapíše init so súhlasom do `check.knownFailures` — zoznamu známych zlyhaní, ktoré commit neblokujú, kým ich niekto neopraví; inak by commit gate blokoval každý commit. PHP šablóny pripájajú audit do `quick` aj `full`, Python do `full`. Plán uvádza skutočný zdroj oznámení a prenášané údaje. Pri chýbajúcom povolenom zdroji ostáva povinný audit zablokovaný.

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
| pred commitom | Pri zapnutej kontrole v Claude alebo Codexe overí kit pre príslušné súbory PASS pre presne ten obsah. Kontroluje aj tajomstvá a zakázané lokálne súbory. Commit spustený priamo v termináli alebo IDE strážia projektové Git hooky. |
| pred editom | Súbory zo `secrets.forbidFiles` (lokálne configy, `.env`) Claude needituje. Pred zmenou už commitnutej migrácie sa Claude spýta. Počas `/dev:fix` je test zamknutý, takže Claude opraví kód, nie test; zmenu testu cez Bash kontrola hlási ako FAIL. |
| pri štarte session | Karta so stackom, stavom kontajnera, gitom, posledným handoffom a zmenou `devkit.json` od poslednej session. Šablóny skopírované zo staršej verzie kitu pripomenie raz za session (`/dev:project-init --sync`). |
| pred kompakciou | Do pokynov súhrnu pridá stav session: súbory, ktoré Claude menil, výsledok poslednej Stop kontroly a posledný PASS z `/dev:check`, zamknutý test a posledný handoff. Kompakciu nikdy nezastaví. |

Nebežiaci kontajner ani chýbajúci nástroj nič nezablokujú, kontrola sa len preskočí. Výsledok je potom **PARTIAL**: nič nepadlo, ale niektorý krok sa nedal spustiť, takže kód nie je overený — PARTIAL nie je PASS a commit gate commit kódu odmietne. Hláška vypíše kroky, ktoré neprebehli. Pri povinnom projektovom kroku obnov predpoklady a zopakuj celý príkaz. Voliteľné kroky umožňujú odstrániť príčinu (napríklad spustiť kontajner), alebo navrhnúť ti dočasné vypnutie cez `disabledRules` krokov, ktoré sa nedali spustiť — a keď neprebehol žiadny krok, celého `commitGate` (kontrola tajomstiev beží ďalej). Config Claude sám nemení.

## Príkazy

| Príkaz | Na čo |
|---|---|
| `/dev:check [--quick · --full · --auto] [--files …]` | kontroly projektu; PASS odomkne commit |
| `/dev:commit` | kontrola, zoskupenie zmien a jednoriadková správa podľa pravidla o commitoch v pokynoch projektu (bez neho `[#XX] typ: výstih`); nikdy nerobí push |
| `/dev:review [branch [base]] [--security]` | review diffu: bugy, bezpečnosť, súlad s plánom, zastarané projektové pokyny |
| `/dev:mr [base]` | popis PR/MR vetvy (Čo, Prečo, Ako overiť, Riziká, Po nasadení) z diffu, plánu, posledného `/dev:check` a migrácií, s nezávislým review pri povolenej delegácii; PR/MR cez `gh` či `glab` vytvorí len so súhlasom, push nikdy |
| `/dev:deps [balík]` | jedna závislosť naraz: zastarané balíky, update, changelog novej verzie, `/dev:check --full` a commit súborov závislostí; nikdy hromadný `composer update` |
| `/dev:fix` | repro test → zámok testu → oprava kódu → kontrola |
| `/dev:test` | test najprv: RED → GREEN → REFACTOR (PHPUnit, Nette Tester, pytest) |
| `/dev:debug` | logy a stav prostredia → hypotéza → minimálny repro → návrh opravy |
| `/dev:plan` | plán väčšej alebo rizikovej zmeny podľa zvyklostí projektu |
| `/dev:handoff` | stav práce do handoff dokumentu pred `/clear` |
| `/dev:explain` | čo kód robí, z čoho závisí a čo hrozí pri zmene |
| `/dev:learn` | návrhy pre osobné pokyny, projekt alebo spoločný kit |
| `/dev:stats` | čo hooky zachytili a ktoré pravidlá sú najhlučnejšie |
| `/dev:project-init` | lokálny alebo tímový plán nastavenia vrátane kontroly pred commitom |
| `/dev:ecc-production-audit` | audit pred nasadením (len ručne) |

Review — ktorý príkaz kedy:

- `/dev:review` — vlastná zmena pred commitom alebo MR: bugy a bezpečnosť s checklistom Nette, Symfony alebo Python, súlad s plánom v `docs/plans/`, aktuálnosť projektových pokynov; drží `REVIEW.md` projektu (čo hlásiť, čo nie). `--security` pridá hĺbkový bezpečnostný prechod.
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
