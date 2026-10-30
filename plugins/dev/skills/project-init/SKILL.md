---
name: project-init
description: Nastaví dev-kit v projekte — deteguje stack, kontajner a nástroje, ukáže dry-run plán a po súhlase zapíše .claude/devkit.json, rules, permissions a CLAUDE.md. --sync zosúladí skopírované šablóny s novou verziou kitu.
argument-hint: "[--sync|--dry-run]"
disable-model-invocation: true
---
<!-- vychádza z ECC skills/codebase-onboarding + commands/project-init.md @ b92f181, prestavané -->

# /dev:project-init

Argumenty: `$ARGUMENTS`
- bez argumentu → fázy súhlasu 1–4 (kroky 1–6) a záver (krok 8)
- `--dry-run` → len kroky 1–2 (plán bez schválenia), skonči vetou „nič som nezapísal"
- `--sync` → len krok 7; `--sync --dry-run` → krok 7 bez zápisu

## Zásady (platia v každom kroku)

- **Najprv plán, potom zápis.** Pred schválením plánu (fáza 1) nemeň žiadny súbor.
- **Existujúci súbor nikdy neprepíš bez výslovného súhlasu** — návrh ulož do dočasného súboru (scratchpad, inak `mktemp -d`) a ukáž `diff -u`. Schválený plán pokrýva nové súbory a zmeny, ktorých presný obsah plán ukázal (blok `permissions` pred → po, riadky `info/exclude` a `.worktreeinclude`, diff `.gitignore`); iný existujúci súbor má vlastný diff a súhlas.
- Pred úpravou existujúceho súboru: sledovaný (`git ls-files --error-unmatch <súbor>`) s necommitnutými zmenami (`git status --porcelain <súbor>` nie je prázdny) → môže na ňom robiť iná session → nechaj ho a povedz to. Nesledovaný alebo ignorovaný súbor najprv skopíruj do `<súbor>.pred-devkit` (na vrátenie).
- Zapisuj len do projektu. Nikdy: commit, push, `git checkout`/`switch`, štart/stop/reštart kontajnerov, `composer install`, `npm install`. Docker len na čítanie (`docker inspect`, `docker compose … config|ps`); `docker exec` len cez `check.sh` (výnimka: phpstan baseline v kroku 3, so súhlasom).
- Z compose nikdy nevypisuj `environment`, `env_file` ani `secrets` (`config` ich interpoluje z `.env`); pri čítaní YAML pozeraj len `services.*.{container_name,image,volumes,working_dir,ports}`.
- Neháduj. Čo nezistíš, označ „nezistené“: symbol šablóny rieš podľa časti Zástupné symboly (zmaž bez otázky), ostatné zaraď do otázok kroku 2.
- **Najviac 4 otázky za init**, naraz v kroku 2 (schvaľovanie fáz sa nepočíta). Na nejasný stack sa opýtaj hneď v kroku 1 — počíta sa do limitu.
- **Pravidlá projektu majú prednosť pred šablónou** (`AGENTS.md`, `CLAUDE.md`, configy nástrojov). Rozpor vypíš v dry-run ako `šablóna <cesta>:<riadok> ↔ <súbor>:<riadok>`; šablónové pravidlo s rozporom bez súhlasu nekopíruj a nič z projektu kvôli šablóne neprepisuj.
- Šablóny: `${CLAUDE_PLUGIN_ROOT}/templates/` (`<stack>/`, `common/`, `skills/`). Verzia kitu `VER` = `jq -r .version "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json"`.
- Pracuj v koreni hlavného checkoutu (`git rev-parse --show-toplevel`). Vo worktree (`.claude/worktrees/…`) upozorni a pokračuj len so súhlasom.
- Chýba `jq` → povedz `brew install jq` (bez neho hooky kitu nebežia) a skonči. Nie je git repo → povedz, že hooky a `check.sh` stoja na gite, a skonči.
- Bez argumentu a `.claude/devkit.json` už existuje → projekt je nastavený; ponúkni `--sync`, nový init len na výslovnú žiadosť.
- Zástupné symboly sú `{{…}}` bez medzery hneď za `{{` (`{{container}}`, `{{vlastník súboru}}`); `{{ … }}` s medzerou za `{{` (Twig, Latte) a `{{.Name}}` (formát dockeru) nemeň.
- Výstup stručne, ale úplne: záver prvý, potom podklady s dôkazom `súbor:riadok`; JSON a diffy v code blokoch.

## Fázy súhlasu

Súhlas pýtaj len na konci týchto štyroch fáz, vždy jednou správou; medzi nimi pracuj bez otázok.

| Fáza | Kroky | Používateľ schvaľuje |
|---|---|---|
| 1 plán | 1–2 | dry-run: súbory, celý `devkit.json`, blok `permissions` pred → po, lokálne alebo tím (riadky `info/exclude` a `.worktreeinclude`, diff `.gitignore`), B-kusy, odpovede na otázky |
| 2 zápis a overenie | 3–4 | nič nové — zapíš, čo schválila fáza 1, a spusti `check.sh --quick`; súhlas len na riešenie nálezov kontroly (`knownFailures`, baseline, `changedLinesOnly`, vypustenie kroku, `--full`) |
| 3 konvencie | 5 | každú konvenciu zvlášť (`áno 1,3`) |
| 4 `CLAUDE.md` / `AGENTS.md` | 6 | celý nový súbor, `diff -u` a mapu presunov |

## 1. Detekcia (fáza 1 — len čítanie, nezávislé príkazy paralelne)

| Čo | Ako | Výsledok |
|---|---|---|
| stack | `composer.json` require: `nette/application` alebo `nette/nette` → `php-nette`, `symfony/framework-bundle` → `php-symfony`; `pyproject.toml` / `requirements*.txt` → `python`; viac alebo nič → opýtaj sa | `stack` + `composer.json:N` |
| kontajner | compose súbory v koreni, `docker/`, `.docker/` (`docker-compose*.y*ml`, `compose*.y*ml`); najprv `config` cez filter pod tabuľkou (vyrieši relatívne cesty), pri chybe čítaj YAML | služba, ktorej volume mountuje **koreň repa** (zdroj relatívne k adresáru compose súboru, napr. `../:/application` v `docker/`) → `container` (`container_name`; bez neho meno z `docker compose -f <f> ps`, inak sa opýtaj), cieľ mountu → `appRoot`; PHP/Python služba má prednosť pred web/db; DB služba (mysql, mariadb, postgres) → `{{dbContainer}}` (len text v `CLAUDE.md`, nie pole `devkit.json`) |
| stav kontajnera | `docker inspect -f '{{.State.Running}}' <c>` | beží / nebeží (nespúšťaj ho) |
| bez kontajnera | žiadny compose alebo mount len podadresára | `container: ""` a `appRoot: ""` (príkazy na hostiteľovi z koreňa repa); nástroje over na hostiteľovi: `command -v php composer python3`, spustiteľné `vendor/bin/<nástroj>` alebo `.venv/bin/<nástroj>`; nebežia tam → otázka 1 v kroku 2 |
| nástroje | `ls vendor/bin`; Python `.venv/bin`, sekcie `[tool.*]` v `pyproject.toml` | phpstan, phpunit, tester, phpcs, latte-lint, phinx, rector, php-cs-fixer, pytest, ruff, mypy |
| DB vrstva (php-nette) | kandidáti len z `require` (nie `require-dev`): `dibi/dibi` → dibi; `doctrine/orm` alebo `nettrine/orm` → doctrine; `nette/database` sám → bez DB pravidiel šablóny, vedľa Dibi alebo Doctrine ho len spomeň (nie je to druhý kandidát). Dôkazy: `extensions:` v neon, `*doctrine*.neon`, adresár entít (`#[ORM\Entity]`), `phinx.*` vs. konfigurácia Doctrine Migrations (`migrations/config.php`, `migrations.php`, sekcia `migrations:` v neon) a jej `migrations_paths`. Jeden kandidát → ten; viac → ukáž dôkazy a opýtaj sa | `db-dibi.md` / `db-doctrine.md`, `migrations.paths`, riadky `<!-- db:… -->` v `CLAUDE.md.tmpl` |
| príkazy Doctrine | `nettrine/*` → `orm:validate-schema`, `migrations:*`; inak `doctrine:*`, ak ich registrácia (`grep -rn 'schema:validate\|validate-schema' app bin config`) alebo `AGENTS.md`/`CLAUDE.md` projektu potvrdí; nezistené → „nezistené“ v pláne (opraví ho odpoveď na otázku 1) | `{{schemaValidateCmd}}`, `{{migrationsCmd}}` |
| Phinx (php-nette) | spustiteľný `vendor/bin/phinx` a config v koreni v poradí, v akom ho hľadá Phinx: `phinx.php`, `phinx.json`, `phinx.yaml`, `phinx.yml` (iný súbor len z `-c`/`--configuration` v `Makefile` alebo `scripts` v `composer.json`). Kľúč `paths.migrations`: JSON `jq '.paths.migrations'`, YAML ako text (blok `paths:`); `phinx.php` **nespúšťaj** — ani `php phinx.php`, ani žiadny príkaz `phinx` (Phinx config načíta cez `include`: autoload projektu, prípadne pripojenie k DB) — len ho čítaj: `grep -nE -A8 "[\"']paths[\"']" phinx.php`. Hodnota je reťazec, pole ciest alebo pole `'<menný priestor>' => '<cesta>'` (berie sa cesta); `'%%PHINX_CONFIG_DIR%%/x'` a `__DIR__ . '/x'` = `x` v adresári configu, cesta bez nich je od adresára, odkiaľ sa phinx spúšťa (koreň repa); premenná, funkcia, konštanta či `getenv` → nezistené | `migrations.paths` = `<cesta>/**` pre každú cestu (`*` ostáva, `{a,b}` rozpíš na položky), cestu mimo `db/` a `migrations/` aj do `fullWhen`; `{{migrationsDir}}` = prvá cesta; config mimo koreňa → príkaz migrácií v `CLAUDE.md` s `-c <config>`; nezistené → otázka 4 s kandidátom (adresár so súbormi `<14 číslic>_*.php`); bez Phinx ostáva `migrations.paths` zo šablóny |
| PHPStan | `phpstan.neon`, `phpstan.neon.dist`, `phpstan.dist.neon`, `app/config/phpstan.neon`, `-c` v `Makefile`; baseline | `{{phpstanConfig}}` |
| PHPUnit | `phpunit.xml*` → `<testsuite name="…">` (presné mená vrátane veľkosti písmen) | kroky `unit` / `integration` |
| Nette Tester (php-nette) | spustiteľný `vendor/bin/tester` a `find tests -name '*.phpt'` neprázdny | krok `tester` namiesto `unit`/`integration`, keď PHPUnit chýba; s PHPUnit oba a `tester` len nad adresárom s `.phpt` (Tester spúšťa aj `*Test.php`); pomalé testy v samostatnom adresári → `integration` len vo full (`_init`); bez Testera krok `tester` a lint `.phpt` vypusť |
| phpcs | ruleset `phpcs.xml`, `.phpcs.xml`, `*.dist` → príkaz bez `--standard` aj bez `--ignore` (vylúčenia rieši ruleset); bez rulesetu → `--standard=PSR12 --ignore=…` zo šablóny; migrácie bez namespace mimo `db/migrations` a `migrations` → doplň ich adresár do `--ignore` | lint príkaz |
| frontend (php-nette, php-symfony) | `package.json`: `eslint`, `stylelint` v `dependencies`/`devDependencies`; config `eslint.config.*`, `.eslintrc*` alebo kľúč `eslintConfig`, resp. `stylelint.config.*`, `.stylelintrc*` alebo kľúč `stylelint`; `node_modules/.bin/<nástroj>` na hostiteľovi | kroky `eslint` / `stylelint` (`runtime: host`) a ich prípony v `commitGate.ext`; bez nástroja alebo configu krok aj prípony vynechaj bez otázky; chýba len `node_modules` → krok ponechaj, pobeží po inštalácii závislostí (spustí ju používateľ) |
| Makefile | ciele test/stan/cs | prevziať príkaz **bez** `make` a bez `-it` (bez TTY padá) |
| kontext | `AGENTS.md` (`wc -l -c`), `CLAUDE.md` (`wc -l -c`, riadok `@AGENTS.md` = import, textová zmienka nie je import), `CLAUDE.local.md`, obsah `.claude/`, `REVIEW.md`, `.worktreeinclude`, `docs/plans/`, migrácie (`db/migrations`, `migrations`, `alembic`) | čo už existuje |
| pravidlá overovania | `AGENTS.md`, `CLAUDE.md`, `Makefile`/skripty projektu: PHPStan config a level, politika baseline, test runner (PHPUnit vs. iný), povinné kontroly | návrh krokov a `{{phpstanConfig}}` podľa nich, nie podľa šablóny |
| git | `git remote -v`, vetva, `git ls-files .claude CLAUDE.md`, `git status --short` | tímový signál, rozpracované súbory |
| handoff | `docs/handoff.md` | `handoffDoc` = `docs/handoff.md`, aj keď ešte neexistuje; sledovaný TODO alebo plán nie — `/dev:handoff` doň pripisuje datované sekcie |
| testovací login | súbor s loginom testovacieho používateľa, ktorý `git check-ignore -q` potvrdí a má commitnutý vzor vedľa (`<súbor>.stub`, `.dist`, `.example`), alebo ho menuje `CLAUDE.md`/`AGENTS.md`; obsah nečítaj | `{{testCredentialsFile}}`; nič → riadok so symbolom zmaž |
| vendor kód v repe | cesty, ktoré `CLAUDE.md` označuje ako „needitovať“ alebo vendor; commitnuté adresáre tretích strán (`git ls-files`: `*framework*/`, `www/js/**/*.min.js`, `assets/vendor/`, `public/vendor/`) | `deny` v pláne (Oprávnenia), `{{vendorFrontendPaths}}` |

Compose bez tajomstiev (`environment`, `env_file` a `secrets` sa nevypíšu):

```bash
docker compose -f <f> config --format json | jq '.services | map_values({container_name, image, volumes, working_dir, ports})'
```

Zhrnutie detekcie: každé zistenie jedným riadkom s dôkazom; hodnoty `{{…}}` podľa časti Zástupné symboly.

## 2. Dry-run plán (fáza 1 — jedna správa, nič sa nezapisuje)

- **Súbory:** `+` nový · `~` zmena existujúceho (diff v pláne alebo vo svojej fáze) · `=` bez zmeny · `!` existuje a líši sa → len so súhlasom.
- **Návrh `devkit.json`** (celý JSON) zo `${CLAUDE_PLUGIN_ROOT}/templates/<stack>/devkit.json`, `{{…}}` vyplň podľa časti Zástupné symboly:
  - kľúče šablóny začínajúce `_` (napr. `_init`) sú pokyny pre teba — prečítaj, do projektu ich nezapisuj;
  - kroky `check.steps` a `lint` len pre existujúce nástroje (vypustené vymenuj, aj „testy kit nespúšťa“, keď projekt nemá PHPUnit, Nette Tester ani pytest), mená testsuite podľa `phpunit.xml`;
  - pravidlá overovania projektu platia už tu: napr. „PHPStan vždy celý projekt“ → krok len s `run` (bez `runFiles` a `changedLinesOnly`), config z projektu;
  - `fullWhen` = jadro projektu (modely, doménová logika, migrácie); `migrations.paths`; `handoffDoc`; `secrets.forbidFiles` = lokálne configy a credentials, ktoré naozaj existujú; projekt používa dlhé hex tokeny (napr. 50 hex v API) → navrhni do `secrets.patterns` `\b[0-9a-f]{N}\b` s presnou dĺžkou (v JSON `\\b`);
  - `pairs`: rady „pri zmene X urob Y" z existujúceho `CLAUDE.md` navrhni ako párové pravidlá (`when` / `unless` / `say`).
- **Bez kontajnera** (`container: ""`): povedz, že lint aj kroky pobežia na hostiteľovi z koreňa repa a `appRoot` sa nepoužije; pri každom kroku a lint príkaze uveď výsledok overenia nástroja (`command -v <nástroj>`, `vendor/bin/<nástroj>`, `.venv/bin/<nástroj>`); chýbajúci nástroj → krok vypusti a vymenuj.
- **DB vrstva** (php-nette) s dôkazom `composer.json:N` a **rozpory šablóny s pravidlami projektu** (zásady).
- **Pravidlá:** ktoré `templates/<stack>/rules/*.md` (s ich `paths:`), čo pôjde do `projekt-*.md` (krok 6) a `conventions.md` (krok 5).
- **Oprávnenia:** cieľový súbor a presný blok `permissions` pred → po (nižšie).
- **Lokálne alebo tím:** režim navrhni podľa gitu z kroku 1 a ukáž jeho presné riadky do `info/exclude` a `.worktreeinclude`, alebo diff `.gitignore` (nižšie).
- **Ďalej:** `.worktreeinclude`, `REVIEW.md` (z `common/`), vrstva B z `${CLAUDE_PLUGIN_ROOT}/templates/skills/*/SKILL.md` — meno + 1 riadok z `description`; odporuč len tie, pre ktoré má projekt signál (dizajn systém/CSS, verejné API, legacy kód, verejný web).
- **CLAUDE.md / AGENTS.md:** čo navrhuješ (lokálne `CLAUDE.local.md`, nový `CLAUDE.md` nie), každá zmena jedným riadkom (detail v kroku 6).
- **Otázky naraz (max 4):** 1) potvrdiť kontajner a príkazy — compose chýba: hostiteľ (`container: ""`) alebo meno kontajnera · 2) lokálne (len ty, `.git/info/exclude`) alebo tím (na commit) · 3) ktoré B-kusy · 4) len ak treba, v jednej otázke: `{{projectDescription}}` a `{{commitStyle}}`, keď ich detekcia nedala; DB vrstva pri viacerých kandidátoch; adresár migrácií Phinx, keď ho `paths.migrations` nedal (s kandidátom); súhlas s rozpornými šablónovými rules.
- **Schválenie plánu = súhlas fázy 1** so všetkým, čo plán presne ukázal. Odpoveď, ktorá plán mení (iný režim, iný kontajner), → ukáž zmenené časti ešte raz pred zápisom.

### Oprávnenia v pláne

- Zdroj `${CLAUDE_PLUGIN_ROOT}/templates/<stack>/settings.json`: `permissions.ask` = brány nad zdieľaným prostredím, `permissions.deny` = vendor cesty.
- Make ciele obchádzajú brány šablóny: ciele, ktoré `Makefile` naozaj má a ktoré zastavia či prestavia kontajnery alebo menia DB či index (napr. `stop`, `down`, `restart`, `rebuild`, `destroy`, `init`, `db-import`, `db-migrate`, `*-reset`, `*-baseline`, `fixtures`), navrhni do `ask` ako `Bash(make <cieľ>*)`.
- Cieľ: tím → `.claude/settings.json`; lokálne → vždy `.claude/settings.local.json` (vylúčenie z gitu rieši Lokálne alebo tím).
- Zlúčenie len pridáva, zachová poradie, nič nemaže, do `allow` nič nedáva (neexistujúci cieľ = `{}`):
  `jq -s '.[0] as $p | (.[1].permissions // {}) as $t | $p | .permissions.ask = (($p.permissions.ask // []) as $a | $a + (($t.ask // []) - $a)) | .permissions.deny = (($p.permissions.deny // []) as $d | $d + (($t.deny // []) - $d))' <cieľ> <vyplnená-šablóna>`
- Do commitnutých settings nepridávaj `enabledPlugins` ani `extraKnownMarketplaces` (kolegovia marketplace kitu zatiaľ nemajú).
- Vendor kód v repe z kroku 1 navrhni do `deny` ukotvene ku koreňu: adresár `Edit(/<cesta>/**)`, vzor súborov `Edit(/www/js/**/*.min.js)`. Rovnaký zoznam použi pre `{{vendorFrontendPaths}}`.
- Heslo alebo token v existujúcich `allow` pravidlách len nahlás, needituj.

### Lokálne alebo tím v pláne

- **Lokálne:** riadky do `"$(git rev-parse --git-common-dir)/info/exclude"` (spoločný pre všetky worktree), len chýbajúce: vždy `.claude/worktrees/` (aj keď ešte žiadny worktree neexistuje) a pre nesledované súbory, ktoré init vytvorí: `.claude/devkit.json`, `.claude/rules/`, `.claude/skills/<meno>/`, `.claude/settings.local.json` (ak ho git ešte neignoruje — vytvorený nástrojom Write sa sám nevylúči), `.worktreeinclude`, `REVIEW.md`, `CLAUDE.local.md`, `*.pred-devkit`, nesledovaný `handoffDoc` (`docs/handoff.md` založí až `/dev:handoff`) a `docs/plans/` (plány z `/dev:plan` ostávajú lokálne — v lokálnom režime z kitu nič nejde do gitu). Už sledované súbory exclude neskryje — povedz to.
- **Lokálne, `.worktreeinclude`:** `.claude/rules/`, `CLAUDE.local.md` a `REVIEW.md` — len tie, ktoré init vytvorí a vylúči — a vždy `docs/plans/` (plán úlohy má byť aj vo worktree). `claude --worktree` ich inak nemá: z hlavného checkoutu sa čítajú len skills, agents a commands, a ignorovaný `CLAUDE.local.md` existuje len vo svojom checkoute. Súbor neexistuje → vytvor ho s hlavičkou `# dev-kit: <stack>/.worktreeinclude @ <VER>`. Nepridávaj `.claude/settings.local.json` (súhlasy sa čítajú z hlavného checkoutu), `.claude/skills/` (čítajú sa z hlavného checkoutu) ani `.claude/devkit.json` (skripty kitu siahnu po kópii v hlavnom checkoute).
- **Tím:** nič nevylučuj. Diff `.gitignore` s riadkom `.claude/worktrees/`. Súbory na commit vypíš v závere, necommituj (ponúkni `/dev:commit`).

`--dry-run` končí tu.

## 3. Zápis a overenie (fáza 2)

1. Lokálne: najprv riadky do `info/exclude` z plánu (pred prvým novým súborom), over `git check-ignore -v <cesta>`. Tím: riadok do `.gitignore`.
2. Zapíš `.claude/devkit.json` (existuje → diff + súhlas, neznáme kľúče používateľa zachovaj). Over `jq -e .version .claude/devkit.json`.
3. Zapíš blok `permissions` z plánu do cieľa (zlúčenie vyššie).
4. Spusti `bash "${CLAUDE_PLUGIN_ROOT}/scripts/check.sh" --quick --project "${CLAUDE_PROJECT_DIR}"`.
5. Exit kód:
   - `0` PASS → ďalej;
   - `3` chyba configu → oprav JSON, spusti znova;
   - `4` neúplné overenie: `SKIP` (nič nebežalo, zvyčajne nebežiaci kontajner) alebo `PARTIAL` (riadok `! <krok>` — nástroj chýba, chyba prostredia) → povedz to, kontajner nespúšťaj, `knownFailures` nenavrhuj; pri `!` navrhni opravu príkazu alebo `requires`;
   - `1` FAIL → pri každom kroku rozlíš chybu príkazu (cesta, suite, config → oprav `devkit.json`) od chyby v kóde (pôvodný stav).
     - Statická analýza alebo linter (phpstan, phpcs, mypy, latte-lint, eslint, stylelint) padá na nezmenenom stave → `knownFailures` sa na ňu nevzťahuje (len PHPUnit `Trieda::metóda`, pytest `FAILED` a Nette Tester `-- FAILED:`); z (a)–(c) ponúkni len to, čo pravidlá projektu nevylučujú (napr. „celý projekt, bez baseline“ → bez (a) aj (b)) a čo nástroj vie (eslint bez (b): výstup nemá cestu na riadku nálezu), so súhlasom: (a) phpstan baseline: `php vendor/bin/phpstan analyse -c <cfg> --generate-baseline <cfg-dir>/phpstan-baseline.neon` (v kontajneri `docker exec -i -w <appRoot> <container>`) + `includes:` v configu, (b) `"changedLinesOnly": true` pre krok, (c) vypustiť krok; latte-lint neprejde nezmenené šablóny (vlastné tagy appky) → vypusť `.latte` lint aj krok `latte`.
6. `– <krok>: chýba <cesta>` → navrhni opravu `requires`/príkazu alebo vypustenie kroku (`node_modules/.bin/…` → stačí inštalácia závislostí, spustí ju používateľ). `– <krok>: žiadne zmenené súbory` (krok len s `runFiles`) → over ho raz cez `--files <1–2 existujúce súbory s jeho ext>`; stále SKIP → v závere „neoverené".
7. **`knownFailures` len so súhlasom**, po krokoch: ukáž padajúce identifikátory (PHPUnit `N) <id>`, pytest `FAILED <id>`, Nette Tester `-- FAILED: <id>` — id je cesta s argumentmi `method=…` bez titulku pred ` | `) a návrh `{"step": "<krok>", "pattern": "^<id>$"}` — v `<id>` escapuj ERE metaznaky (`\ . [ ] ( ) { } * + ? | ^ $`), v JSON každú `\` zdvoj (`Tests\\\\Unit\\\\FooTest::testX`). Povedz dôsledok: bez nich commit gate zablokuje každý commit kvôli starým chybám; alternatíva je opraviť ich.
8. Kroky len pre `full` (napr. integration): ponúkni `--full` ako východiskový stav (bez neho commit gate pri zmene vo `fullWhen` narazí na staré chyby). Beží minúty → len po súhlase, Bash s `timeout: 600000` alebo na pozadí; padajúce testy ako v bode 7.

## 4. Kopírovanie šablón (fáza 2)

- Hlavička `<!-- dev-kit: <cesta> @ <VER> -->`, `<cesta>` relatívne k `${CLAUDE_PLUGIN_ROOT}/templates/` (napr. `php-nette/rules/db-dibi.md`, `common/REVIEW.md`, `skills/ecc-seo/SKILL.md`):
  - YAML frontmatter → hlavička na riadok hneď za uzatváracie `---` (frontmatter musí ostať prvý, inak sa `paths:` neuplatní);
  - `.worktreeinclude` → `# dev-kit: <stack>/.worktreeinclude @ <VER>` (HTML komentár by bol vzor);
  - JSON súbory a `CLAUDE.md` hlavičku nemajú (krok 7 porovnáva JSON podľa `id`, CLAUDE.md je projektový).
- php-nette: z `db-dibi.md` a `db-doctrine.md` len ten pre DB vrstvu z kroku 1 (oba len na výslovnú voľbu); `nette/database` bez Dibi a Doctrine → žiadny.
- Rules: `templates/<stack>/rules/<f>.md` → `.claude/rules/<f>.md`. **Kopírovať, nikdy symlink** (symlinkované path-scoped rules sa nenačítajú). `{{…}}` podľa časti Zástupné symboly.
- Šablónové kópie nechaj čisté; projektový obsah patrí do `projekt-*.md` a `conventions.md` → `--sync` bez konfliktov.
- `.worktreeinclude`: zo šablóny len riadky, ktoré v projekte existujú a sú gitignored (`git check-ignore -q <cesta>`); existujúci súbor → doplň chýbajúce riadky.
- `REVIEW.md` do koreňa: popisné `{{…}}` vyplň z detekcie bez otázky — vendor a generované cesty (krok 1, `deny`), nástroj na štýl a na analýzu (kroky `devkit.json`), zámerné rozhodnutia a pasce review (`CLAUDE.md`, `AGENTS.md`), vlastník (`CODEOWNERS`); nezistené → zmaž položku (pri vlastníkovi vetu „Vlastník: …"), nadpisy sekcií ostanú.
- Vrstva B: `templates/skills/<meno>/` → `.claude/skills/<meno>/` (hlavička v `SKILL.md`).

## 5. infer-conventions (fáza 3)

- Hľadaj **nedefaultné, dobre podložené** konvencie: ≥ 3 výskyty v ≥ 2 súboroch, protipríklady ≤ 10 % (uveď počet). Legacy vs. nový kód (`git log --since=6.months --name-only`) sa líši → platí nový kód, povedz to.
- Oblasti: pomenovanie (triedy, testy, migrácie), DI (konštruktor vs. `inject*`), chyby (výnimky vs. návratové hodnoty), DB (parametre, model/repository), šablóny a JS kotvy, testy (base triedy, rollback, fixtures), commit správy (`git log --format=%s -50`).
- Preskoč: čo vymáha phpcs/PHPStan/rector/php-cs-fixer/ruff/mypy (prečítaj ich config), defaulty PSR-12 a frameworku, čo už je v `CLAUDE.md` alebo rules.
- Výstup: všetky konvencie, ktoré prešli filtrom, zoradené podľa sily dôkazu: `N. <konvencia ako pokyn> — dôkaz: a.php:12, b.php:40, c.php:7 (k/n)`.
- Schvaľuje sa po jednom (`áno 1,3`). Schválené → `.claude/rules/conventions.md`: `paths:` = globy pokrývajúce dôkazy, 1 pokyn = 1 riadok, ≤ 60 riadkov, bez hlavičky `dev-kit:`. Konvencie bez súborového rozsahu (commit správy) patria do `CLAUDE.md` (lokálne `CLAUDE.local.md`).

## 6. CLAUDE.md a AGENTS.md (fáza 4, ≤ 120 riadkov)

- **`AGENTS.md` existuje** (spoločné pravidlá pre viac nástrojov):
  - projektový obsah kostry (Projekt, Stack, Príkazy, Architektúra, Pravidlá, Pasce) navrhni ako diff do `AGENTS.md`; bez `/dev:*`, `.claude/` a iných vecí len pre Claude;
  - `CLAUDE.md` = prvý riadok `@AGENTS.md` + len časti pre Claude (riadok `/dev:check` a overovanie cez neho, odkaz na `.claude/rules/`, Compact instructions); obsah `AGENTS.md` v ňom neopakuj;
  - `CLAUDE.md` už existuje a `AGENTS.md` len spomína textom → zmienku zmaž a `@AGENTS.md` daj na prvý riadok (diff, súhlas);
  - `CLAUDE.md` bez `@AGENTS.md` nikdy nevytváraj: Claude Code číta `AGENTS.md` sám len vtedy, keď `CLAUDE.md` ani `CLAUDE.local.md` neexistuje;
  - `AGENTS.md` nerozsekávaj do `.claude/rules/` (ostatné nástroje by o pravidlá prišli); lokálny režim → `AGENTS.md` ani sledovaný `CLAUDE.md` neupravuj, `@AGENTS.md` a časti pre Claude daj do `CLAUDE.local.md`.
- **Bez `AGENTS.md`:** ako doteraz, nižšie.

- Kostra `${CLAUDE_PLUGIN_ROOT}/templates/<stack>/CLAUDE.md.tmpl`: Projekt · Stack · Príkazy · Architektúra · Pravidlá · Pasce · 3 riadky pre kompakciu. Úvodný komentár šablóny `<!-- … -->` sú pokyny pre teba — do `CLAUDE.md` ho neprenášaj. `{{…}}` podľa časti Zástupné symboly. Riadky so značkou `<!-- db:dibi -->` / `<!-- db:doctrine -->`: ponechaj len vrstvu z kroku 1, značku odstráň aj s medzerou pred ňou (v tabuľke stojí pred posledným `|`). Zoznam rules v Pravidlách uprav na skutočne skopírované.
- **Overovací blok (V9):** ku každému príkazu tvar zdravého výstupu (`OK (… tests, … assertions)`, `[OK] No errors`) z reálneho behu v kroku 3 — bez presných počtov testov a časov, tie zastarávajú.
- **3 riadky pre kompakciu** zo šablóny ponechaj (zmenené súbory + stav `/dev:check` · otvorené rozhodnutia + ďalší krok · príkazy na overenie).
- `CLAUDE.md` neexistuje → tím: vyplň kostru z detekcie do `CLAUDE.md`; lokálne: nový `CLAUDE.md` nevytváraj (lokálny režim nedáva do gitu nič a `CLAUDE.md` patrí tímu) — vyplnenú kostru zapíš do `CLAUDE.local.md`.
- `CLAUDE.md` existuje:
  - tematické sekcie (frontend, DB, testy, API, doména) → `.claude/rules/projekt-<téma>.md` s `paths:` na súbory, ktorých sa týkajú;
  - pravidlo, ktorého strata spôsobí regresiu mimo jedného adresára → v CLAUDE.md ostane 1 riadok + odkaz (path-scoped rule sa načíta až pri práci so zhodným súborom);
  - zastarané príkazy a čísla oprav podľa krokov 1 a 3.
- Pred zápisom ukáž celý nový `CLAUDE.md` (lokálne `CLAUDE.local.md`), `diff -u` a **mapu presunov** `CLAUDE.md:<od>-<do> „<sekcia>" → <cieľ>` + vypustené riadky s dôvodom. Každé pravidlo skončí práve na jednom mieste.
- Veľký prepis (> 30 % riadkov) len s výslovným súhlasom.
- **Lokálny režim a `CLAUDE.md` v gite → nerozsekávaj** (tím by o presunuté pravidlá prišiel, rules sú mimo gitu). Overovací blok a riadky kompakcie navrhni do `CLAUDE.local.md`.
- Lokálne, po zápise: do `.worktreeinclude` doplň riadky z plánu (len súbory, ktoré init naozaj vytvoril a vylúčil).

## 7. `--sync` (aktualizácia skopírovaných šablón)

1. Súbory s hlavičkou: `grep -rlE --exclude-dir=worktrees '^(<!--|#) dev-kit: ' .claude REVIEW.md .worktreeinclude 2>/dev/null || true` (chýbajúci súbor = exit 2, zoznam platí); z hlavičky `<cesta>` a starú verziu `OLD` (bez prípadného `v`).
2. Pre každý: `TEMPLATE` = `${CLAUDE_PLUGIN_ROOT}/templates/<cesta>`, `LOCAL` = súbor bez riadku hlavičky; `{{…}}` v šablónach vyplň rovnako ako v `LOCAL` (premenované symboly majú v časti Zástupné symboly aj starý názov).
   - šablóna zmizla → navrhni zmazanie (súhlas);
   - `LOCAL` == `TEMPLATE` → `= aktuálne` (len zdvihni verziu v hlavičke);
   - `BASE` = šablóna vo verzii `OLD`: `git -C "${CLAUDE_PLUGIN_ROOT}" show "dev--v<OLD>:./templates/<cesta>"` (funguje, keď je kit git repo s release tagmi);
   - s `BASE` → `git merge-file -p LOCAL BASE TEMPLATE` (lokálne úpravy ostanú); bez `BASE` → `diff -u LOCAL TEMPLATE` po blokoch: prevziať / ponechať.
3. Per súbor ukáž diff výsledku, zapíš až po súhlase, v hlavičke nastav `@ <VER>`. Konfliktné značky (`<<<<<<<`) nikdy nezapíš — vyrieš ich s používateľom.
4. Nové súbory šablóny, ktoré projekt nemá (rules, B-kusy) → ponúkni ako v kroku 4; php-nette: DB vrstva = skopírovaný `db-*.md`, inak detekcia z kroku 1 — Dibi projektu neponúkaj `db-doctrine.md` ani položky `doctrine-*`, Doctrine projektu `db-dibi.md`. Rovnako chýbajúce riadky z časti Lokálne alebo tím v pláne (režim: `.claude/devkit.json` v gite = tím, inak lokálne): `.claude/worktrees/`, nesledovaný `handoffDoc` a `docs/plans/` v `info/exclude` (lokálne) alebo `.claude/worktrees/` v `.gitignore` (tím, so súhlasom); lokálne `.claude/rules/`, `CLAUDE.local.md`, `REVIEW.md` (len existujúce a ignorované) a `docs/plans/` v `.worktreeinclude`.
5. `devkit.json` a settings (bez hlavičky): porovnaj `guards`, `pairs`, `check.steps` podľa `id` a `permissions.ask`/`deny` so šablónou; navrhni **nové** položky (bez `doctrine-*` mimo Doctrine projektu; krok `eslint`/`stylelint` len podľa detekcie frontendu z kroku 1 a spolu s ním jeho prípony do `commitGate.ext`; krok `tester` len keď krok 1 našiel Nette Tester, spolu s `.phpt` do `lint` a `commitGate.ext`; cesty Phinx z kroku 1, ktoré `migrations.paths` nepokrýva, ako `<cesta>/**`, mimo `db/` a `migrations/` aj do `fullWhen`). Položka s rovnakým `id`, ktorá sa líši od šablóny: zhoduje sa so šablónou verzie `OLD` (z hlavičiek rules; `git -C "${CLAUDE_PLUGIN_ROOT}" show "dev--v<OLD>:./templates/<stack>/devkit.json"`, `{{…}}` vyplnené ako v projekte) → navrhni novú hodnotu (diff, súhlas); inak ju projekt zmenil → len vypíš rozdiel, nemeň ju.
6. Súhrn: tabuľka súbor · stav (aktualizované/aktuálne/konflikt/nové) · čo sa zmenilo.

## 8. Záver

- Vytvorené / zmenené: zoznam ciest.
- Commit: tím → zoznam na commit (`/dev:commit`) vrátane `.gitignore` s `.claude/worktrees/`; lokálne → „v `.git/info/exclude` (aj `.claude/worktrees/`), nič na commit“.
- Worktree: kam išiel `.claude/worktrees/` a ktoré riadky pribudli do `.worktreeinclude` (lokálne).
- Vrátenie: nové súbory `rm <cesty>`; sledované zmenené `git checkout -- <cesta>`; nesledované zmenené `mv <súbor>.pred-devkit <súbor>`. Po overení `*.pred-devkit` zmaž (nie sú na commit).
- Kedy platí: hooky čítajú `devkit.json` hneď; `CLAUDE.md` a rules po `/clear` alebo v novej session.
- Ďalší krok: jedna veta (napr. `/dev:check --full` ako východiskový stav integration testov).

## Zástupné symboly

Platí pre `{{…}}` v šablónach `<stack>/` (`devkit.json`, `CLAUDE.md.tmpl`, rules); `common/plan.md` vypĺňa `/dev:plan`, popisné `{{…}}` v `common/REVIEW.md` rieši krok 4.

- Detekovateľné vyplň a v pláne ukáž s dôkazom `súbor:riadok`.
- Nezistené rieš bez otázky podľa stĺpca Nezistené: „zmaž“ = riadok, ktorý je len o symbole (odrážka, riadok tabuľky či stromu), inak najmenšiu časť riadku, ktorá bez symbolu nedáva zmysel (` · {{database}}`, ` level {{phpstanLevel}}`, ` ({{appUrl}})`, vedľajšiu vetu za `;`); „len číslo“ = zmaž len verziu. Krok alebo pair `devkit.json` s nezisteným symbolom vypusti a vymenuj v pláne.
- Pýtaj sa len na `{{projectDescription}}`, `{{commitStyle}}` (git log bez histórie alebo bez jednotného štýlu), `{{container}}` (compose chýba) a `{{migrationsDir}}` pri Phinx, keď sa `paths.migrations` nedá prečítať bez spustenia configu — v otázkach kroku 2, limit 4 ostáva.
- Symbol adresára (`…Dir`) končí `/`; v `devkit.json` z neho glob `{{entityDir}}**`.

Stack: N = php-nette, S = php-symfony, P = python.

| Symbol | Stack | Zdroj | Nezistené |
|---|---|---|---|
| `{{projectName}}` | N S P | `name` v `composer.json` (časť za `/`) alebo v `pyproject.toml`, inak meno adresára repa | — |
| `{{projectDescription}}` | N S P | `description` v `composer.json`/`pyproject.toml`, prvý odsek `README.md` alebo `AGENTS.md` | otázka 4 |
| `{{domainTerms}}` | N P | glosár alebo zoznam pojmov v `CLAUDE.md`, `AGENTS.md`, `README.md` | zmaž |
| `{{architectureNotes}}` `{{projectPitfalls}}` | N P | vstupné body a vzory, resp. pasce z existujúceho `CLAUDE.md`/`AGENTS.md` | zmaž |
| `{{commitStyle}}` | N P | `git log --format=%s -50`: prefix úlohy, `typ:`, jazyk | otázka 4 |
| `{{handoffDoc}}` | N P | krok 1 handoff (`docs/handoff.md`) | — |
| `{{testCredentialsFile}}` | N | krok 1 testovací login | zmaž |
| `{{container}}` `{{appRoot}}` | N S P | krok 1 kontajner: `container_name`, cieľ mountu koreňa repa | compose chýba → otázka 1; `container: ""` → oba `""`, riadok Docker v Stacku zmaž |
| `{{dbContainer}}` | N | DB služba v compose (krok 1); len text v `CLAUDE.md`, pole `devkit.json` to nie je | zmaž |
| `{{run}}` | N S P | `docker exec {{container}} ` (keď `working_dir` služby nie je `{{appRoot}}`: `docker exec -w {{appRoot}} {{container}} `); P aj `.venv/bin/` alebo `uv run ` | `""` (hostiteľ) |
| `{{bin}}` | P | `_init` v `devkit.json`: `.venv/bin/`, `/opt/venv/bin/` v kontajneri | `""` (nástroje v PATH) |
| `{{pythonEnv}}` | P | podľa `{{run}}`: venv `.venv` na hostiteľovi, uv, alebo kontajner `{{container}}` | — |
| `{{appUrl}}` | N P | lokálna URL v `README.md`/`CLAUDE.md`/`AGENTS.md`, inak `ports` webovej služby (`8080:80` → `http://localhost:8080`) | zmaž |
| `{{startCommand}}` `{{startHealthyOutput}}` | N P | cieľ `Makefile` (`up`, `start`) alebo príkaz z `README.md`; zdravý výstup z toho istého zdroja | zmaž riadok |
| `{{phpVersion}}` | N S | `require.php` alebo `config.platform.php` v `composer.json`, image PHP služby | len číslo |
| `{{netteVersion}}` `{{latteVersion}}` `{{dibiVersion}}` `{{ormVersion}}` `{{symfonyVersion}}` | N (`symfonyVersion` S) | `composer.lock`: `nette/application`, `latte/latte`, `dibi/dibi`, `doctrine/orm`, `symfony/framework-bundle` (major.minor), inak obmedzenie v `require` | len číslo |
| `{{pythonVersion}}` | P | `requires-python` v `pyproject.toml`, `.python-version`, image v compose | len číslo |
| `{{database}}` | N S P | image DB služby v compose (`mysql:8.0` → MySQL 8.0), `server_version` v konfigurácii Doctrine | zmaž |
| `{{framework}}` | P | závislosť `django`, `flask`, `fastapi` … v `pyproject.toml`/`requirements*.txt` | zmaž |
| `{{phpstanConfig}}` `{{phpstanLevel}}` | N S (`phpstanLevel` N) | krok 1 PHPStan; `level:` v jeho configu | bez PHPStan krok `phpstan` vypusti; level zmaž |
| `{{mypyTarget}}` | P | `_init` v `devkit.json` | `.` |
| `{{packageManager}}` `{{installCommand}}` | P | lock súbor: `uv.lock` → uv, `uv sync`; `poetry.lock` → Poetry, `poetry install`; `requirements*.txt` → pip, `{{run}}pip install -r requirements.txt` | zmaž |
| `{{migrationTool}}` `{{migrateCommand}}` `{{migrateHealthyOutput}}` | P | `alembic.ini` → Alembic, `alembic upgrade head`; Django `manage.py` → `python manage.py migrate`, `No migrations to apply.` | zmaž |
| `{{package}}` | P | balík v `src/<balík>/` s `__init__.py` | riadok stromu uprav podľa repa |
| `{{entityDir}}` `{{repositoryDir}}` | N (Doctrine) | adresár tried s `#[ORM\Entity]`, resp. `extends EntityRepository`; do 0.3.x v `devkit.json` `entityGlob` = `{{entityDir}}**` | pair `doctrine-entity-migration` vypusti; zmaž |
| `{{migrationsDir}}` | N | Doctrine: `migrations_paths` z konfigurácie migrácií (krok 1); Phinx: prvá cesta z `paths.migrations` (krok 1); do 0.3.x `migrationsGlob` = `{{migrationsDir}}**` | Phinx s configom → otázka 4; inak pair `doctrine-entity-migration` vypusti; zmaž |
| `{{schemaValidateCmd}}` `{{migrationsCmd}}` | N (Doctrine) | krok 1 príkazy Doctrine | krok `doctrine-schema` vypusti; zmaž |
| `{{doctrineNeon}}` | N (Doctrine) | `*doctrine*.neon` v `app/config/` (krok 1 DB vrstva) | zmaž |
| `{{baseModel}}` | N (Dibi) | najčastejší rodič (`extends`) tried v `app/models/` | zmaž |
| `{{securedPresenter}}` | N | presenter, ktorého `startup()` overuje prihlásenie a ostatné ho dedia | zmaž riadok |
| `{{frontendStack}}` | N | `package.json` (bundler, knižnice), commitnuté knižnice z kroku 1 | zmaž riadok |
| `{{vendorFrontendPaths}}` | N | krok 1 vendor kód (rovnaký zoznam ako `deny`) | `""` |

## Pasce

- `make` ciele s `docker exec -it` bez TTY padnú → do `devkit.json` vždy priamy príkaz.
- Mená testsuite sú citlivé na veľkosť písmen (`unit` ≠ `Unit`).
- `docker compose config` zlyhá na chýbajúcom `.env` → čítaj YAML a cesty rieš relatívne k adresáru compose súboru.
- Kontajner mountuje len podadresár → worktree mapovanie nefunguje, `check.sh` kroky preskočí.
- `paths:` v rules sú relatívne ku koreňu projektu (adresár s `.claude/`).
