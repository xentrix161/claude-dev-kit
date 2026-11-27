# Plán a inštalácia nastavení projektu

Pri prvom inite priprav kroky 1–2. Podľa [pravidiel pre commit](commit-hook.md) vlož do toho istého plánu aj výsledok inventára hookov. Pri podporovanom stacku použi [tabuľku symbolov](symbols.md). Pri projekte bez vhodnej šablóny zostav konfiguráciu z overených projektových vstupov a vynechaj kroky pre kopírované šablóny.

## Zásady (platia v každom kroku)

- **Najprv plán, potom zápis.** Pred schválením plánu (fáza 1) nemeň žiadny súbor.
- **Existujúci súbor nikdy neprepíš bez výslovného súhlasu** — návrh ulož do dočasného súboru (scratchpad, inak `mktemp -d`) a ukáž `diff -u`. Schválený plán pokrýva nové súbory a zmeny, ktorých presný obsah plán ukázal (blok `permissions` a ostatné kľúče settings pred → po, riadky `info/exclude` a `.worktreeinclude`, diff `.gitignore`); iný existujúci súbor má vlastný diff a súhlas.
- Pred úpravou existujúceho súboru: sledovaný (`git ls-files --error-unmatch <súbor>`) s necommitnutými zmenami (`git status --porcelain <súbor>` nie je prázdny) → môže na ňom robiť iná session → nechaj ho a povedz to. Nesledovaný alebo ignorovaný súbor najprv skopíruj do `<súbor>.pred-devkit` (na vrátenie).
- Zapisuj len do projektu. Nikdy: commit, push, `git checkout`/`switch`, štart/stop/reštart kontajnerov, `composer install`, `npm install`. Docker len na čítanie (`docker inspect`, `docker compose … config|ps`); `docker exec` len cez `check.sh` (výnimky: `docker exec <c> sh -c 'command -v composer'` v kroku 1 pre krok `audit`, phpstan baseline v kroku 3 so súhlasom).
- Z compose nikdy nevypisuj `environment`, `env_file` ani `secrets` (`config` ich interpoluje z `.env`); pri čítaní YAML pozeraj len `services.*.{container_name,image,volumes,working_dir,ports}`.
- Neháduj. Čo nezistíš, označ „nezistené“: symbol šablóny rieš podľa časti Zástupné symboly (zmaž bez otázky), ostatné zaraď do otázok kroku 2.
- **Najviac 4 otázky za init**, naraz v kroku 2 (schvaľovanie fáz sa nepočíta). Otázku na variant šablóny polož len pri výslovnej požiadavke na jej inštaláciu.
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
| 1 plán | 1–2 | dry-run: súbory, celý `devkit.json` (aj odosielanie zoznamu balíkov krokom `audit`), blok `permissions` a ostatné kľúče settings pred → po, lokálne alebo tím (riadky `info/exclude` a `.worktreeinclude`, diff `.gitignore`), B-kusy, odpovede na otázky |
| 2 zápis a overenie | 3–4 | nič nové — zapíš, čo schválila fáza 1, a over konfiguráciu podľa jej fázy v kroku 3; súhlas len na riešenie nálezov kontroly (`knownFailures`, baseline, `changedLinesOnly`, vypustenie kroku, `commitGate` pri SKIP, `--full`) |
| 3 konvencie | 5 | každú konvenciu zvlášť (`áno 1,3`) |
| 4 `AGENTS.md` | 6 | celý nový súbor, `diff -u` a mapu presunov |

## 1. Detekcia (fáza 1 — len čítanie, nezávislé príkazy paralelne)

Pri zvolenej PHP šablóne doplň [detekciu PHP](php.md) a príslušného frameworku, [Nette](nette.md) alebo [Symfony](symfony.md). Pre Python stačia riadky nižšie.

| Čo | Ako | Výsledok |
|---|---|---|
| stack | `composer.json` require: `nette/application` alebo `nette/nette` → `php-nette`, `symfony/framework-bundle` → `php-symfony`; `pyproject.toml` / `requirements*.txt` → `python`; viac alebo nič → pokračuj generickým postupom | `stack` + `composer.json:N` |
| kontajner | compose súbory v koreni, `docker/`, `.docker/` (`docker-compose*.y*ml`, `compose*.y*ml`); najprv `config` cez filter pod tabuľkou (vyrieši relatívne cesty), pri chybe čítaj YAML | služba, ktorej volume mountuje **koreň repa** (zdroj relatívne k adresáru compose súboru, napr. `../:/application` v `docker/`) → `container` (`container_name`; bez neho meno z `docker compose -f <f> ps`, inak sa opýtaj), cieľ mountu → `appRoot`; PHP/Python služba má prednosť pred web/db; DB služba (mysql, mariadb, postgres) → `{{dbContainer}}` (len text v `AGENTS.md`, nie pole `devkit.json`) |
| stav kontajnera | `docker inspect -f '{{.State.Running}}' <c>` | beží / nebeží (nespúšťaj ho) |
| bez kontajnera | žiadny compose alebo mount len podadresára | `container: ""` a `appRoot: ""` (príkazy na hostiteľovi z koreňa repa); nástroje over na hostiteľovi: `command -v php composer python3`, spustiteľné `vendor/bin/<nástroj>` alebo `.venv/bin/<nástroj>`; nebežia tam → voliteľný krok vypusti, povinný vykáž ako zablokovaný a otázka 1 v kroku 2; mount len podadresára → kit kontajner nepoužije (aj to otázka 1) |
| nástroje | `ls vendor/bin`; Python `.venv/bin`, sekcie `[tool.*]` v `pyproject.toml` | phpstan, phpunit, tester, phpcs, latte-lint, neon-lint, phinx, rector, php-cs-fixer, pytest, ruff, mypy |
| audit závislostí | Najprv vyhľadaj projektový príkaz v harnessoch a CI vrátane Make alebo kontajnerového wrappera. PHP s lockfile používa audit v `quick` aj `full`. Bez vlastného vstupu over Composer v určenom runtime. Python používa projektový audit alebo `pip-audit` 2.7+ vo `full`. | Schválený zdroj a príkaz podľa kroku 2. Chýbajúci predpoklad povinného auditu vykáž ako zablokovaný. Ak príkaz alebo povolený spôsob vykonania nevieš určiť, zastav aktiváciu. Vypustiť možno iba voliteľný krok. |
| Makefile | projektové ciele pre testy, analýzu, audit a štýl | Použi celý príkaz, napr. `make stan`, vrátane jeho predpokladov a prostredia. Over, že funguje bez TTY. Ak vyžaduje TTY, použi existujúci projektový vstup pre CI alebo vykáž zablokovanie. |
| kontext | `AGENTS.md` (`wc -l -c`), `CLAUDE.md` (`wc -l -c`, riadok `@AGENTS.md` = import, textová zmienka nie je import), `CLAUDE.local.md`, obsah `.claude/`, `REVIEW.md`, `.worktreeinclude`, `docs/plans/`, migrácie (`db/migrations`, `migrations`, `alembic`) | čo už existuje |
| pravidlá overovania | `AGENTS.md`, `CLAUDE.md`, `Makefile`/skripty projektu: PHPStan config a level, politika baseline, test runner (PHPUnit vs. iný), povinné kontroly | doslovný `{{phpstanCommand}}` v dokumentácii aj v `run`, `runtime: host` zahŕňa aj explicitný kontajnerový wrapper |
| git | `git remote -v`, vetva, `git ls-files .claude AGENTS.md CLAUDE.md`, `git status --short` | tímový signál, rozpracované súbory |
| handoff | `docs/handoff.md` | `handoffDoc` = `docs/handoff.md`, aj keď ešte neexistuje; sledovaný TODO alebo plán nie — `/dev:handoff` doň pripisuje datované sekcie |
| testovací login | súbor s loginom testovacieho používateľa, ktorý `git check-ignore -q` potvrdí a má commitnutý vzor vedľa (`<súbor>.stub`, `.dist`, `.example`), alebo ho menuje `CLAUDE.md`/`AGENTS.md`; obsah nečítaj | `{{testCredentialsFile}}`; nič → riadok so symbolom zmaž |
| vendor kód v repe | cesty, ktoré projektové pokyny označujú ako „needitovať“ alebo vendor; commitnuté adresáre tretích strán (`git ls-files`: `*framework*/`, `www/js/**/*.min.js`, `assets/vendor/`, `public/vendor/`) | `deny` v pláne (Oprávnenia), `{{vendorFrontendPaths}}` |

Compose bez tajomstiev (`environment`, `env_file` a `secrets` sa nevypíšu):

```bash
docker compose -f <f> config --format json | jq '.services | map_values({container_name, image, volumes, working_dir, ports})'
```

Zhrnutie detekcie: každé zistenie jedným riadkom s dôkazom; hodnoty `{{…}}` podľa časti Zástupné symboly.

## 2. Dry-run plán (fáza 1 — jedna správa, nič sa nezapisuje)

- **Súbory:** `+` nový · `~` zmena existujúceho (diff v pláne alebo vo svojej fáze) · `=` bez zmeny · `!` existuje a líši sa → len so súhlasom.
- Pri každom pripájanom kroku vrátane Stop over, ktoré údaje projekt povoľuje uchovať. Ak povoľuje iba stav, nastav `output: status`. Ak obmedzuje aj metadáta ako cesty súborov, príkaz nechaj v projektovom harness-e a použi jeho povolený report. V pláne vyznač povinné kontroly, ktoré treba doložiť samostatne.
- **Návrh `devkit.json`** (celý JSON) zo `${CLAUDE_PLUGIN_ROOT}/templates/<stack>/devkit.json`, `{{…}}` vyplň podľa časti Zástupné symboly:
  - kľúče šablóny začínajúce `_` (napr. `_init`) sú pokyny pre teba — prečítaj, do projektu ich nezapisuj; `$schema` (schéma pre editor) ponechaj;
  - voliteľné kroky `check.steps` a `lint` len pre existujúce nástroje (vypustené vymenuj, aj „testy kit nespúšťa“, keď projekt nemá PHPUnit, Nette Tester ani pytest), mená testsuite podľa `phpunit.xml`;
  - pri výslovnom pripojení povinnej projektovej kontroly nastav `required: true`, pôvodný celý `run`, príslušné `modes` a pri výbere z nepripraveného diffu `phase: before-stage`. Pri nových cestách vo fáze `before-stage` zisti, ako natívny krok dokladá skutočný výber a výnimky. Prevezmi jeho schválený adaptér a `newPathsReport` podľa [schémy kitu](../../../devkit.schema.json). Ak existujúci vstup taký výsledok neposkytuje, over inú projektom schválenú sadu nad pripraveným obsahom alebo vykáž chýbajúci dôkaz. Testovacie wrappery prevezmi aj pri nástrojoch nainštalovaných iba v kontajneri. Pri chýbajúcom nástroji ponechaj povinný krok viditeľný ako PARTIAL. Ostatné pravidlá overovania projektu platia už tu: napr. „PHPStan vždy celý projekt“ → krok len s `run` (bez `runFiles` a `changedLinesOnly`), config z projektu;
  - `fullWhen` = jadro projektu (modely, doménová logika, migrácie); `migrations.paths`; `handoffDoc`; `secrets.forbidFiles` = lokálne configy a credentials, ktoré naozaj existujú; projekt používa dlhé hex tokeny (napr. 50 hex v API) → navrhni do `secrets.patterns` `\b[0-9a-f]{N}\b` s presnou dĺžkou (v JSON `\\b`);
  - `pairs`: rady „pri zmene X urob Y" z projektových pokynov navrhni ako párové pravidlá (`when` / `unless` / `say`).
- **Bez kontajnera** (`container: ""`): povedz, že lint aj kroky pobežia na hostiteľovi z koreňa repa a `appRoot` sa nepoužije; pri každom kroku a lint príkaze uveď výsledok overenia nástroja (`command -v <nástroj>`, `vendor/bin/<nástroj>`, `.venv/bin/<nástroj>`); chýbajúci voliteľný nástroj → krok vypusti a vymenuj.
- Pri chýbajúcom alebo zlyhanom povinnom kroku ukáž pôvodný verdikt a príčinu. Návrhy na vypustenie, baseline, výnimky a vypnutie gate v nasledujúcich krokoch platia len pre voliteľné kontroly.
- **Kontrola bez kroku:** iba pri konfigurácii so samými voliteľnými krokmi alebo bez krokov. Keď v `check.steps` neostane krok s `run` a režimom `quick`, ktorého nástroj init našiel, `/dev:check` dá SKIP (exit 4) bez `pass.json` aj `partial.json` a commit gate taký commit zablokuje bez úniku: bez krokov každý, s krokmi len s `runFiles` každý bez existujúceho súboru s ich príponou, aj commit, ktorý súbory len maže (kroky dostanú len existujúce súbory, gate ráta aj zmazané). Plán to povie výslovne, návrh `devkit.json` má `"commitGate": {"enabled": false, …}` aj pri krokoch s `runFiles` (zúžené `commitGate.ext` zmazanie nepokryje; tajomstvá, guardy, lint a Stop bežia ďalej) a otázka 1 ponúkne namiesto toho kontajner alebo nástroje na hostiteľovi; odpoveď, ktorá taký krok vráti, vráti aj `enabled: true`.
- Pri PHP pláne najprv mapuj audit lockfile a PHPStan na natívny harness. Ak má spoločný vstup, nechaj jediný povinný krok a v tabuľke naň odkáž pre obe kontroly. Zisti, ktoré unit, integračné a E2E scenáre pokrývajú zmenený tok. Ak E2E či integračný príkaz existuje, prepoj ho so zodpovedajúcim rozsahom (natívny výber alebo `fullWhen` a povinný krok vo `full`). Pri chýbajúcej sade popíš medzeru. Zachovaj projektovú politiku, vrátane povinného zablokovaného kroku. Pri chýbajúcom povolení na externý zdroj nevytváraj spustiteľný krok s takým prístupom. Zachovaj pôvodný gate a odlož aktiváciu, kým nebude dostupný povolený vstup.
- **Audit závislostí:** V pláne uveď skutočný zdroj bezpečnostných oznámení (napr. Packagist alebo PyPI), aké údaje príkaz odosiela a v ktorých režimoch beží. Schválenie plánu je súhlas s týmto prístupom. Ak prístup chýba, použi schválený projektový zdroj alebo vykáž povinný audit ako zablokovaný. Voliteľný audit môže používateľ vypustiť.
- **DB vrstva** (php-nette) s dôkazom `composer.json:N` a **rozpory šablóny s pravidlami projektu** (zásady).
- **Pravidlá:** ktoré `templates/<stack>/rules/*.md` (s ich `paths:`), čo pôjde do `projekt-*.md` (krok 6) a `conventions.md` (krok 5).
- **Oprávnenia a nastavenia:** cieľový súbor a presný blok `permissions` a ostatné kľúče settings pred → po (nižšie).
- **Lokálne alebo tím:** ukáž spoločnú konfiguráciu raz. Pri každom variante uveď presný rozdiel pre `info/exclude`, `.worktreeinclude`, `.gitignore` a príslušné settings podľa časti Lokálne alebo tím. Pri tímovom variante uveď aj osobné predpoklady, ktoré musí mať každý klient.
- **Ďalej:** `.worktreeinclude`, `REVIEW.md` (z `common/`), vrstva B z `${CLAUDE_PLUGIN_ROOT}/templates/skills/*/SKILL.md` — meno + 1 riadok z `description`; odporuč len tie, pre ktoré má projekt signál (dizajn systém/CSS, verejné API, legacy kód, verejný web).
- **AGENTS.md:** prípadný tímový diff. Osobný režim žiadny súbor pravidiel nevytvára.
- **Otázky naraz (max 4):** 1) potvrdiť kontajner a príkazy — compose chýba: hostiteľ (`container: ""`) alebo meno kontajnera; compose mountuje len podadresár (kroky by v ňom neboli z koreňa repa): hostiteľ, alebo mount koreňa repa upraví používateľ a init pokračuje s kontajnerom; Kontrola bez kroku: kontajner či nástroje na hostiteľovi, inak gate vypnutý podľa návrhu · 2) lokálne (len ty, `.git/info/exclude`) alebo tím (na commit); v tej istej otázke, či skryť atribúciu Claude v commitoch a PR (`attribution`, predvolene nie — bez zmeny) · 3) ktoré B-kusy · 4) len ak treba, v jednej otázke: `{{projectDescription}}` a `{{commitStyle}}`, keď ich detekcia nedala; `{{localConfig}}` (php-nette), keď ho nenašla; DB vrstva pri viacerých kandidátoch; adresár migrácií Phinx, keď ho `paths.migrations` nedal (s kandidátom); súhlas s rozpornými šablónovými rules.
- **Schválenie plánu = súhlas fázy 1** so zobrazeným variantom vrátane kontroly pred commitom. Vyžiadaj si schválenie vybraného variantu v jednej odpovedi. Pri odmietnutí skonči bez zápisu. Pri úprave mimo zobrazených variantov ukáž zmenené časti pred zápisom.

### Oprávnenia a nastavenia v pláne

- Zdroj `${CLAUDE_PLUGIN_ROOT}/templates/<stack>/settings.json`: `permissions.ask` = brány nad zdieľaným prostredím, deštruktívnymi príkazmi git a docker a zmenou závislostí, `permissions.deny` = vendor cesty; ďalej `plansDirectory`, `extraKnownMarketplaces` a `enabledPlugins`.
- Make ciele obchádzajú brány šablóny: ciele, ktoré `Makefile` naozaj má a ktoré zastavia či prestavia kontajnery alebo menia DB či index (napr. `stop`, `down`, `restart`, `rebuild`, `destroy`, `init`, `db-import`, `db-migrate`, `*-reset`, `*-baseline`, `fixtures`), navrhni do `ask` ako `Bash(make <cieľ>*)`.
- Cieľ: tím → `.claude/settings.json`; lokálne → vždy `.claude/settings.local.json` (vylúčenie z gitu rieši Lokálne alebo tím).
- `plansDirectory: "docs/plans"` (plány z režimu plánovania ležia vedľa plánov `/dev:plan`) do cieľa v oboch režimoch. `extraKnownMarketplaces` (`dev-kit` z GitHubu) a `enabledPlugins` (`dev@dev-kit`) len v tímovom režime do `.claude/settings.json` — kolega po prijatí dôvery priečinka dostane marketplace kitu a plugin zapnutý; v lokálnom režime ich vynechaj. Kľúč, ktorý cieľ už má, nemeň (ani `"dev@dev-kit": false`), len ho ukáž.
- `attribution` podľa otázky 2: áno → `"attribution": {"commit": "", "pr": "", "sessionUrl": false}` do cieľa (tvar, ktorý čítajú aj staršie verzie Claude Code; hodnotu `false` by odmietli spolu s celým súborom); predvolene nie → kľúč nepridávaj a existujúci nemeň.
- Zlúčenie len pridáva, zachová poradie a hodnoty projektu, nič nemaže, do `allow` nič nedáva (neexistujúci cieľ = `{}`, `team` = `true` v tímovom režime, inak `false`):
  ```bash
  jq -s --argjson team <true|false> '.[0] as $p | .[1] as $s | ($s.permissions // {}) as $t | $p
    | .permissions.ask = (($p.permissions.ask // []) as $a | $a + (($t.ask // []) - $a))
    | .permissions.deny = (($p.permissions.deny // []) as $d | $d + (($t.deny // []) - $d))
    | .plansDirectory = ($p.plansDirectory // $s.plansDirectory)
    | if $team then .extraKnownMarketplaces = (($s.extraKnownMarketplaces // {}) + ($p.extraKnownMarketplaces // {}))
        | .enabledPlugins = (($s.enabledPlugins // {}) + ($p.enabledPlugins // {})) else . end' <cieľ> <vyplnená-šablóna>
  ```
- Vendor kód v repe z kroku 1 navrhni do `deny` ukotvene ku koreňu: adresár `Edit(/<cesta>/**)`, vzor súborov `Edit(/www/js/**/*.min.js)`. Rovnaký zoznam použi pre `{{vendorFrontendPaths}}`.
- Heslo alebo token v existujúcich `allow` pravidlách len nahlás, needituj.

### Lokálne alebo tím v pláne

- **Lokálne:** riadky do `"$(git rev-parse --git-common-dir)/info/exclude"` (spoločný pre všetky worktree), len chýbajúce: vždy `.claude/worktrees/` (aj keď ešte žiadny worktree neexistuje) a pre nesledované súbory, ktoré init vytvorí: `.claude/devkit.json`, `.claude/rules/`, `.claude/skills/<meno>/`, `.claude/settings.local.json` (ak ho git ešte neignoruje — vytvorený nástrojom Write sa sám nevylúči), `.worktreeinclude`, `REVIEW.md`, `*.pred-devkit`, nesledovaný `handoffDoc` (`docs/handoff.md` založí až `/dev:handoff`) a `docs/plans/` (plány z `/dev:plan` ostávajú lokálne — v lokálnom režime z kitu nič nejde do gitu). Už sledované súbory exclude neskryje — povedz to.
- **Lokálne, `.worktreeinclude`:** `.claude/rules/` a `REVIEW.md` — len tie, ktoré init vytvorí a vylúči — a vždy `docs/plans/` (plán úlohy má byť aj vo worktree). `claude --worktree` ich inak nemá: z hlavného checkoutu sa čítajú len skills, agents a commands, a ignorovaný `CLAUDE.local.md` existuje len vo svojom checkoute. Súbor neexistuje → vytvor ho s hlavičkou `# dev-kit: <stack>/.worktreeinclude @ <VER>`. Nepridávaj `.claude/settings.local.json` (súhlasy sa čítajú z hlavného checkoutu), `.claude/skills/` (čítajú sa z hlavného checkoutu) ani `.claude/devkit.json` (skripty kitu siahnu po kópii v hlavnom checkoute).
- **Tím:** do `info/exclude` len nesledovaný `handoffDoc` (osobný stav práce, do ktorého `/dev:handoff` pripisuje — kolegom do gitu nepatrí; sledovaný exclude neskryje — povedz to), nič iné nevylučuj. Pre každú navrhovanú nesledovanú tímovú cestu prever `git check-ignore -v --no-index -- <cesta>`. V diffe `.gitignore` zahrň `.claude/worktrees/` a úzke výnimky pre ignorované tímové súbory. Ak projekt ignoruje celý adresár, sprístupni rodiča, znovu vylúč jeho obsah a povoľ iba dohodnuté súbory. Rovnako postupuj pre vnorené adresáre. `.claude/settings.json` dostane `extraKnownMarketplaces` a `enabledPlugins` (Oprávnenia a nastavenia) — Claude môže po prijatí dôvery načítať plugin. Účinný Git hook a osobnú registráciu v Codexe over v danom checkoute. Súbory na commit vypíš v závere, necommituj (ponúkni `/dev:commit`).

Príklad výnimiek, keď projekt ignoruje celý adresár a schválil iba dva tímové súbory:

```gitignore
!/.claude/
/.claude/*
!/.claude/devkit.json
!/.claude/settings.json
```

`--dry-run` končí tu.

## 3. Zápis a overenie (fáza 2)

1. Lokálne: najprv riadky do `info/exclude` z plánu (pred prvým novým súborom), over `git check-ignore -v <cesta>`. Tím: schválený diff `.gitignore` a nesledovaný `handoffDoc` do `info/exclude`. Po vytvorení over každú tímovú cestu cez `git ls-files --cached --others --exclude-standard -- <cesta>`. Výstup musí obsahovať daný súbor. Pri osobných súboroch, ktoré boli ignorované, potvrď ich ďalšie vylúčenie cez `git check-ignore`. Rozpor ohlás pred označením nastavenia za zdieľateľné.
2. Zapíš `.claude/devkit.json` (existuje → diff + súhlas, neznáme kľúče používateľa zachovaj). Over `jq -e .version .claude/devkit.json`.
3. Zapíš blok `permissions` a ostatné kľúče settings z plánu do cieľa (zlúčenie vyššie).
4. Pri bežnom kroku spusti `bash "${CLAUDE_PLUGIN_ROOT}/scripts/check.sh" --quick --project "${CLAUDE_PROJECT_DIR}"`. Ak konfigurácia vyžaduje `before-stage` v `quick`, over najprv nepripravený obsah s `--quick --before-stage` a čistým indexom. Pri existujúcom stagingu zachovaj index a použi izolovaný worktree s rovnakou konfiguráciou a reprezentatívnou zmenou, alebo oznám, ktorá fáza ešte čaká. Samotný init nepripravuje súbory používateľa na commit. Bežnú kontrolu finálneho indexu vykonaj až pri zamýšľanom stagingu. Prvý úspešný krok dokladá iba vykonanú fázu.
5. Exit kód:
   - `0` PASS → ďalej;
   - `3` chyba configu → oprav JSON, spusti znova;
   - `4` neúplné overenie: `SKIP` (nič nebežalo, len riadky `–`: krok chýba, chýba jeho `requires`, žiadne zmenené súbory) alebo `PARTIAL` (riadok `! <krok>` — kontajner nebeží, príkaz sa nedá spustiť, chyba prostredia) → povedz to, kontajner nespúšťaj, `knownFailures` nenavrhuj; pri chýbajúcom výsledku pred stagingom sa vráť ku kroku 4, pri chýbajúcom predpoklade over príkaz a `requires`; SKIP výhradne voliteľných krokov pri zapnutom commit gate a bez kroku s `run` v `quick`, ktorý pobeží, → Kontrola bez kroku (krok 2): navrhni `commitGate.enabled: false` (aj keď ostali kroky s `runFiles`), inak gate commit so SKIP zablokuje bez úniku;
   - `1` FAIL → pri každom kroku rozlíš chybu príkazu (cesta, suite, config → oprav `devkit.json`) od chyby v kóde (pôvodný stav).
     - Statická analýza alebo linter (phpstan, phpcs, mypy, latte-lint, eslint, stylelint) padá na nezmenenom stave → `knownFailures` sa na ňu nevzťahuje (len PHPUnit `Trieda::metóda`, pytest `FAILED` a `ERROR`, Nette Tester `-- FAILED:` a zraniteľnosti kroku `audit`); z (a)–(c) ponúkni len to, čo pravidlá projektu nevylučujú (napr. „celý projekt, bez baseline“ → bez (a) aj (b)) a čo nástroj vie (eslint bez (b): výstup nemá cestu na riadku nálezu), so súhlasom: (a) phpstan baseline: `php vendor/bin/phpstan analyse -c <cfg> --generate-baseline <cfg-dir>/phpstan-baseline.neon` (v kontajneri `docker exec -i -w <appRoot> <container>`) + `includes:` v configu, (b) `"changedLinesOnly": true` pre krok, (c) vypustiť krok; latte-lint neprejde nezmenené šablóny (vlastné tagy appky) → vypusť `.latte` lint aj krok `latte`.
6. `– <krok>: chýba <cesta>` → navrhni opravu `requires`/príkazu alebo vypustenie kroku (`node_modules/.bin/…` → stačí inštalácia závislostí, spustí ju používateľ). `– <krok>: žiadne zmenené súbory` (krok len s `runFiles`) → over ho raz cez `--files <1–2 existujúce súbory s jeho ext>`; stále SKIP → v závere „neoverené".
7. **`knownFailures` len pre voliteľné kroky so súhlasom**: ukáž padajúce identifikátory (PHPUnit `N) <id>`, pytest `FAILED <id>` a `ERROR <id>` (`<cesta>::<test>`, pri chybe zberu len cesta), Nette Tester `-- FAILED: <id>` — id je cesta s argumentmi `method=…` bez titulku pred ` | `; `audit`: `Advisory ID:` a `CVE:` z `composer audit`, stĺpec `ID` a aliasy z `pip-audit` — vzor na jedno id pokryje celý záznam, napr. `^CVE-2026-12345$`) a návrh `{"step": "<krok>", "pattern": "^<id>$"}` — v `<id>` escapuj ERE metaznaky (`\ . [ ] ( ) { } * + ? | ^ $`), v JSON každú `\` zdvoj (`Tests\\\\Unit\\\\FooTest::testX`). Povedz dôsledok: bez nich commit gate zablokuje každý commit kvôli starým chybám; alternatíva je opraviť ich.
8. Kroky len pre `full` (napr. integration, migration, Python audit): ponúkni `--full` ako východiskový stav (bez neho commit gate pri zmene vo `fullWhen` narazí na staré chyby). Beží minúty → len po súhlase, Bash s `timeout: 600000` alebo na pozadí; padajúce testy ako v bode 7.

## 4. Kopírovanie šablón (fáza 2)

- Hlavička `<!-- dev-kit: <cesta> @ <VER> -->`, `<cesta>` relatívne k `${CLAUDE_PLUGIN_ROOT}/templates/` (napr. `php-nette/rules/db-dibi.md`, `common/REVIEW.md`, `skills/ecc-seo/SKILL.md`):
  - YAML frontmatter → hlavička na riadok hneď za uzatváracie `---` (frontmatter musí ostať prvý, inak sa `paths:` neuplatní);
  - `.worktreeinclude` → `# dev-kit: <stack>/.worktreeinclude @ <VER>` (HTML komentár by bol vzor);
  - JSON súbory a `AGENTS.md` hlavičku nemajú (krok 7 porovnáva JSON podľa `id`, AGENTS.md je projektový).
- php-nette: z `db-dibi.md` a `db-doctrine.md` len ten pre DB vrstvu z kroku 1 (oba len na výslovnú voľbu); `nette/database` bez Dibi a Doctrine → žiadny.
- php-symfony: `api-platform.md` len keď krok 1 našiel balík `api-platform/*` v `composer.json`; v `twig-frontend.md` ponechaj riadky so značkou `<!-- fe:… -->` zisteného frontendu (značku odstráň aj s medzerou pred ňou), riadky iného variantu zmaž.
- Rules: `templates/<stack>/rules/<f>.md` → `.claude/rules/<f>.md`. **Kopírovať, nikdy symlink** (symlinkované path-scoped rules sa nenačítajú). `{{…}}` podľa časti Zástupné symboly.
- Šablónové kópie nechaj čisté; projektový obsah patrí do `projekt-*.md` a `conventions.md` → `--sync` bez konfliktov.
- `.worktreeinclude`: zo šablóny len riadky, ktoré v projekte existujú a sú gitignored (`git check-ignore -q <cesta>`); existujúci súbor → doplň chýbajúce riadky.
- `REVIEW.md` do koreňa: popisné `{{…}}` vyplň z detekcie bez otázky — vendor a generované cesty (krok 1, `deny`), nástroj na štýl a na analýzu (kroky `devkit.json`), zámerné rozhodnutia a pasce review (`CLAUDE.md`, `AGENTS.md`), vlastník (`CODEOWNERS`); nezistené → zmaž položku (pri vlastníkovi vetu „Vlastník: …"), nadpisy sekcií ostanú.
- Vrstva B: `templates/skills/<meno>/` → `.claude/skills/<meno>/` (hlavička v `SKILL.md`).

## 5. infer-conventions (fáza 3)

- Hľadaj **nedefaultné, dobre podložené** konvencie: ≥ 3 výskyty v ≥ 2 súboroch, protipríklady ≤ 10 % (uveď počet). Legacy vs. nový kód (`git log --since=6.months --name-only`) sa líši → platí nový kód, povedz to.
- Oblasti: pomenovanie (triedy, testy, migrácie), DI (konštruktor vs. `inject*`), chyby (výnimky vs. návratové hodnoty), DB (parametre, model/repository), šablóny a JS kotvy, testy (base triedy, rollback, fixtures), commit správy (`git log --format=%s -50`).
- Preskoč: čo vymáha phpcs/PHPStan/rector/php-cs-fixer/ruff/mypy (prečítaj ich config), defaulty PSR-12 a frameworku, čo už je v projektových pokynoch.
- Výstup: všetky konvencie, ktoré prešli filtrom, zoradené podľa sily dôkazu: `N. <konvencia ako pokyn> — dôkaz: a.php:12, b.php:40, c.php:7 (k/n)`.
- Schvaľuje sa po jednom (`áno 1,3`). Schválené → `.claude/rules/conventions.md`: `paths:` = globy pokrývajúce dôkazy, 1 pokyn = 1 riadok, ≤ 60 riadkov, bez hlavičky `dev-kit:`. Konvencie bez súborového rozsahu (commit správy) patria do tímového `AGENTS.md`. V osobnom režime ich len vypíš.

## 6. Spoločné pokyny projektu

- V tímovom režime je cieľom `AGENTS.md`. Ak chýba, ukáž návrh z overených projektových príkazov. Podkladom je `templates/<stack>/AGENTS.md.tmpl`. Zahrň používané nástroje a odkazy na existujúcu dokumentáciu. Pri existujúcom súbore navrhni iba chýbajúci údaj.
- Osobný režim ponechá projektové pokyny pri pôvodnom obsahu. Init aj sync ponechajú `CLAUDE.md` a `CLAUDE.local.md` ich vlastníkovi. Ak miestny súbor tieni `AGENTS.md`, vysvetli načítanie. Migráciu existujúcich pokynov rieš osobitným diffom.
- Značky variantu šablóny a zástupné symboly vyhodnoť podľa kroku 4. Ku kontrole doplň pozorovaný tvar zdravého výstupu. Nevykonaný krok označ ako neoverený.

## 8. Záver

- Vytvorené / zmenené: zoznam ciest.
- Commit: tím → zoznam na commit (`/dev:commit`) vrátane `.gitignore` s `.claude/worktrees/` a `.claude/settings.json` (kolegovia po dôvere priečinka dostanú marketplace `dev-kit` a plugin `dev`), `handoffDoc` ostáva mimo gitu (`info/exclude`); lokálne → „v `.git/info/exclude` (aj `.claude/worktrees/`), nič na commit“.
- Worktree: kam išiel `.claude/worktrees/` a ktoré riadky pribudli do `.worktreeinclude` (lokálne).
- Vrátenie: nové súbory `rm <cesty>`; sledované zmenené `git checkout -- <cesta>`; nesledované zmenené `mv <súbor>.pred-devkit <súbor>`. Po overení `*.pred-devkit` zmaž (nie sú na commit).
- Kedy platí: hooky čítajú `devkit.json` hneď; projektové pokyny a rules po `/clear` alebo v novej session.
- Ďalší krok: jedna veta (napr. `/dev:check --full` ako východiskový stav integration testov).

## Pasce

- Ak projektový cieľ vyžaduje TTY, postupuj podľa detekcie Makefile v kroku 1 vrátane jeho predpokladov.
- Mená testsuite sú citlivé na veľkosť písmen (`unit` ≠ `Unit`).
- `docker compose config` zlyhá na chýbajúcom `.env` → čítaj YAML a cesty rieš relatívne k adresáru compose súboru.
- Kontajner mountuje len podadresár → worktree mapovanie nefunguje, `check.sh` kroky preskočí.
- `paths:` v rules sú relatívne ku koreňu projektu (adresár s `.claude/`).
