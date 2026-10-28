---
name: project-init
description: Nastaví dev-kit v projekte — deteguje stack, kontajner a nástroje, ukáže dry-run plán a so súhlasom zapíše .claude/devkit.json, rules, permissions a kostru CLAUDE.md. --sync zosúladí skopírované šablóny s novou verziou kitu.
argument-hint: "[--sync|--dry-run]"
disable-model-invocation: true
---
<!-- vychádza z ECC skills/codebase-onboarding + commands/project-init.md @ b92f181, prestavané -->

# /dev:project-init

Argumenty: `$ARGUMENTS`
- bez argumentu → kroky 1–10, zápis až po schválení plánu
- `--dry-run` → len kroky 1–2, skonči vetou „nič som nezapísal"
- `--sync` → len krok 9; `--sync --dry-run` → krok 9 bez zápisu

## Zásady (platia v každom kroku)

- **Najprv plán, potom zápis.** Pred schválením konkrétneho plánu nemeň žiadny súbor.
- **Existujúci súbor nikdy neprepíš bez výslovného súhlasu** — návrh ulož do dočasného súboru (scratchpad, inak `mktemp -d`) a ukáž `diff -u`. Súhlas s plánom pokrýva len nové súbory.
- Pred úpravou existujúceho súboru: sledovaný (`git ls-files --error-unmatch <súbor>`) s necommitnutými zmenami (`git status --porcelain <súbor>` nie je prázdny) → môže na ňom robiť iná session → nechaj ho a povedz to. Nesledovaný alebo ignorovaný súbor najprv skopíruj do `<súbor>.pred-devkit` (na vrátenie).
- Zapisuj len do projektu. Nikdy: commit, push, `git checkout`/`switch`, štart/stop/reštart kontajnerov, `composer install`. Docker len na čítanie (`docker inspect`, `docker compose … config|ps`); `docker exec` len cez `check.sh` (výnimka: phpstan baseline v kroku 3, so súhlasom).
- Z compose nikdy nevypisuj `environment`, `env_file` ani `secrets` (`config` ich interpoluje z `.env`); pri čítaní YAML pozeraj len `services.*.{container_name,image,volumes,working_dir}`.
- Neháduj. Čo nezistíš, označ „nezistené" a opýtaj sa — jedna konkrétna otázka.
- Šablóny: `${CLAUDE_PLUGIN_ROOT}/templates/` (`<stack>/`, `common/`, `skills/`). Verzia kitu `VER` = `jq -r .version "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json"`.
- Pracuj v koreni hlavného checkoutu (`git rev-parse --show-toplevel`). Vo worktree (`.claude/worktrees/…`) upozorni a pokračuj len so súhlasom.
- Chýba `jq` → povedz `brew install jq` (bez neho hooky kitu nebežia) a skonči. Nie je git repo → povedz, že hooky a `check.sh` stoja na gite, a skonči.
- Bez argumentu a `.claude/devkit.json` už existuje → projekt je nastavený; ponúkni `--sync`, nový init len na výslovnú žiadosť.
- Zástupné symboly sú `{{…}}` bez medzery hneď za `{{` (`{{container}}`, `{{vlastník súboru}}`); `{{ … }}` s medzerou za `{{` (Twig, Latte) a `{{.Name}}` (formát dockeru) nemeň.
- Výstup stručne, ale úplne: záver prvý, potom podklady s dôkazom `súbor:riadok`; JSON a diffy v code blokoch.

## 1. Detekcia (len čítanie, nezávislé príkazy paralelne)

| Čo | Ako | Výsledok |
|---|---|---|
| stack | `composer.json` require: `nette/application` alebo `nette/nette` → `php-nette`, `symfony/framework-bundle` → `php-symfony`; `pyproject.toml` / `requirements*.txt` → `python`; viac alebo nič → opýtaj sa | `stack` + `composer.json:N` |
| kontajner | compose súbory v koreni, `docker/`, `.docker/` (`docker-compose*.y*ml`, `compose*.y*ml`); najprv `config` cez filter pod tabuľkou (vyrieši relatívne cesty), pri chybe čítaj YAML | služba, ktorej volume mountuje **koreň repa** (zdroj relatívne k adresáru compose súboru, napr. `../:/application` v `docker/`) → `container` (`container_name`; bez neho meno z `docker compose -f <f> ps`, inak sa opýtaj), cieľ mountu → `appRoot`; PHP/Python služba má prednosť pred web/db; DB služba (mysql, mariadb, postgres) → `dbContainer` |
| stav kontajnera | `docker inspect -f '{{.State.Running}}' <c>` | beží / nebeží (nespúšťaj ho) |
| bez kontajnera | žiadny compose alebo mount len podadresára | `container: ""` (príkazy na hostiteľovi), ak tam nástroje bežia; inak sa opýtaj |
| nástroje | `ls vendor/bin`; Python `.venv/bin`, sekcie `[tool.*]` v `pyproject.toml` | phpstan, phpunit, phpcs, latte-lint, rector, php-cs-fixer, pytest, ruff, mypy |
| PHPStan | `phpstan.neon`, `phpstan.neon.dist`, `phpstan.dist.neon`, `app/config/phpstan.neon`, `-c` v `Makefile`; baseline | `phpstanConfig` |
| PHPUnit | `phpunit.xml*` → `<testsuite name="…">` (presné mená vrátane veľkosti písmen) | kroky `unit` / `integration` |
| phpcs | ruleset `phpcs.xml`, `.phpcs.xml`, `*.dist` → príkaz bez `--standard` aj bez `--ignore` (vylúčenia rieši ruleset); bez rulesetu → `--standard=PSR12 --ignore=…` zo šablóny; migrácie bez namespace mimo `db/migrations` a `migrations` → doplň ich adresár do `--ignore` | lint príkaz |
| Makefile | ciele test/stan/cs | prevziať príkaz **bez** `make` a bez `-it` (bez TTY padá) |
| kontext | `CLAUDE.md` (`wc -l -c`), `CLAUDE.local.md`, obsah `.claude/`, `REVIEW.md`, `.worktreeinclude`, `docs/plans/`, migrácie (`db/migrations`, `migrations`, `alembic`) | čo už existuje |
| git | `git remote -v`, vetva, `git ls-files .claude CLAUDE.md`, `git status --short` | tímový signál, rozpracované súbory |
| handoff | `docs/handoff.md` | `handoffDoc` = `docs/handoff.md`, aj keď ešte neexistuje; sledovaný TODO alebo plán nie — `/dev:handoff` doň pripisuje datované sekcie |
| vendor kód v repe | cesty, ktoré `CLAUDE.md` označuje ako „needitovať“ alebo vendor; commitnuté adresáre tretích strán (`git ls-files`: `*framework*/`, `www/js/**/*.min.js`, `assets/vendor/`, `public/vendor/`) | `deny` v kroku 5, `{{vendorFrontendPaths}}` |

Compose bez tajomstiev (`environment`, `env_file` a `secrets` sa nevypíšu):

```bash
docker compose -f <f> config --format json | jq '.services | map_values({container_name, image, volumes, working_dir})'
```

Zhrnutie detekcie: každé zistenie jedným riadkom s dôkazom.

## 2. Dry-run plán (jedna správa, nič sa nezapisuje)

- **Súbory:** `+` nový · `~` zmena existujúceho (diff v jeho kroku) · `=` bez zmeny · `!` existuje a líši sa → len so súhlasom.
- **Worktree (krok 8):** `.claude/worktrees/` → lokálne `info/exclude`, tím `~ .gitignore`; lokálne aj riadky `.claude/rules/`, `CLAUDE.local.md`, `REVIEW.md` do `.worktreeinclude`.
- **Návrh `devkit.json`** (celý JSON) zo `${CLAUDE_PLUGIN_ROOT}/templates/<stack>/devkit.json`, vyplň `{{container}}`, `{{appRoot}}`, `{{phpstanConfig}}` a ostatné `{{…}}`:
  - kľúče šablóny začínajúce `_` (napr. `_init`) sú pokyny pre teba — prečítaj, do projektu ich nezapisuj;
  - kroky `check.steps` a `lint` len pre existujúce nástroje (vypustené vymenuj), mená testsuite podľa `phpunit.xml`;
  - `fullWhen` = jadro projektu (modely, doménová logika, migrácie); `migrations.paths`; `handoffDoc`; `secrets.forbidFiles` = lokálne configy a credentials, ktoré naozaj existujú; projekt používa dlhé hex tokeny (napr. 50 hex v API) → navrhni do `secrets.patterns` `\b[0-9a-f]{N}\b` s presnou dĺžkou (v JSON `\\b`);
  - `pairs`: rady „pri zmene X urob Y" z existujúceho `CLAUDE.md` navrhni ako párové pravidlá (`when` / `unless` / `say`).
- **Pravidlá:** ktoré `templates/<stack>/rules/*.md` (s ich `paths:`), čo pôjde do `projekt-*.md` (krok 7) a `conventions.md` (krok 6).
- **Ďalej:** `.worktreeinclude`, `REVIEW.md` (z `common/`), permissions (krok 5), vrstva B z `${CLAUDE_PLUGIN_ROOT}/templates/skills/*/SKILL.md` — meno + 1 riadok z `description`; odporuč len tie, pre ktoré má projekt signál (dizajn systém/CSS, verejné API, legacy kód, verejný web).
- **CLAUDE.md:** čo navrhuješ, každá zmena jedným riadkom (detail v kroku 7).
- **Otázky naraz (max 3):** 1) potvrdiť kontajner a príkazy · 2) lokálne (len ty, `.git/info/exclude`) alebo tím (na commit) · 3) ktoré B-kusy.

`--dry-run` končí tu.

## 3. `devkit.json` a overenie

1. Zapíš `.claude/devkit.json` (existuje → diff + súhlas, neznáme kľúče používateľa zachovaj). Over `jq -e .version .claude/devkit.json`.
2. Spusti `bash "${CLAUDE_PLUGIN_ROOT}/scripts/check.sh" --quick --project "$(pwd)"`.
3. Exit kód:
   - `0` PASS → ďalej;
   - `3` chyba configu → oprav JSON, spusti znova;
   - `4` nič nebežalo (zvyčajne nebežiaci kontajner) → povedz to, kontajner nespúšťaj, `knownFailures` nenavrhuj;
   - `1` FAIL → pri každom kroku rozlíš chybu príkazu (cesta, suite, config → oprav `devkit.json`) od chyby v kóde (pôvodný stav).
     - Statická analýza alebo linter (phpstan, phpcs, mypy, latte-lint) padá na nezmenenom stave → `knownFailures` sa na ňu nevzťahuje (len PHPUnit `Trieda::metóda` a pytest `FAILED`); so súhlasom ponúkni: (a) phpstan baseline: `php vendor/bin/phpstan analyse -c <cfg> --generate-baseline <cfg-dir>/phpstan-baseline.neon` (v kontajneri `docker exec -i -w <appRoot> <container>`) + `includes:` v configu, (b) `"changedLinesOnly": true` pre krok, (c) vypustiť krok; latte-lint neprejde nezmenené šablóny (vlastné tagy appky) → vypusť `.latte` lint aj krok `latte`.
4. `– <krok>: chýba <cesta>` → navrhni opravu `requires`/príkazu alebo vypustenie kroku. `– <krok>: žiadne zmenené súbory` (krok len s `runFiles`) → over ho raz cez `--files <1–2 existujúce súbory s jeho ext>`; stále SKIP → v závere „neoverené".
5. **`knownFailures` len so súhlasom**, po krokoch: ukáž padajúce identifikátory (PHPUnit `N) <id>`, pytest `FAILED <id>`) a návrh `{"step": "<krok>", "pattern": "^<id>$"}` — v `<id>` escapuj ERE metaznaky (`\ . [ ] ( ) { } * + ? | ^ $`), v JSON každú `\` zdvoj (`Tests\\\\Unit\\\\FooTest::testX`). Povedz dôsledok: bez nich commit gate zablokuje každý commit kvôli starým chybám; alternatíva je opraviť ich.
6. Kroky len pre `full` (napr. integration): ponúkni `--full` ako východiskový stav (bez neho commit gate pri zmene vo `fullWhen` narazí na staré chyby). Beží minúty → len po súhlase, Bash s `timeout: 600000` alebo na pozadí; padajúce testy ako v bode 5.

## 4. Kopírovanie šablón

- Hlavička `<!-- dev-kit: <cesta> @ <VER> -->`, `<cesta>` relatívne k `${CLAUDE_PLUGIN_ROOT}/templates/` (napr. `php-nette/rules/db-dibi.md`, `common/REVIEW.md`, `skills/ecc-seo/SKILL.md`):
  - YAML frontmatter → hlavička na riadok hneď za uzatváracie `---` (frontmatter musí ostať prvý, inak sa `paths:` neuplatní);
  - `.worktreeinclude` → `# dev-kit: <stack>/.worktreeinclude @ <VER>` (HTML komentár by bol vzor);
  - JSON súbory a `CLAUDE.md` hlavičku nemajú (krok 9 porovnáva JSON podľa `id`, CLAUDE.md je projektový).
- Rules: `templates/<stack>/rules/<f>.md` → `.claude/rules/<f>.md`. **Kopírovať, nikdy symlink** (symlinkované path-scoped rules sa nenačítajú). `{{…}}` vyplň z detekcie, neznáme sa opýtaj.
- Šablónové kópie nechaj čisté; projektový obsah patrí do `projekt-*.md` a `conventions.md` → `--sync` bez konfliktov.
- `.worktreeinclude`: zo šablóny len riadky, ktoré v projekte existujú a sú gitignored (`git check-ignore -q <cesta>`); existujúci súbor → doplň chýbajúce riadky.
- `REVIEW.md` do koreňa: `{{…}}` vyplň s používateľom (vlastník, „nehlásiť": vendor cesty, zámerné rozhodnutia z `CLAUDE.md`, čo stráži phpcs/PHPStan).
- Vrstva B: `templates/skills/<meno>/` → `.claude/skills/<meno>/` (hlavička v `SKILL.md`).

## 5. Oprávnenia `permissions` (len so súhlasom, presný JSON)

- Zdroj `${CLAUDE_PLUGIN_ROOT}/templates/<stack>/settings.json`: `permissions.ask` = brány nad zdieľaným prostredím, `permissions.deny` = vendor cesty; `{{…}}` vyplň (napr. meno DB kontajnera).
- Make ciele obchádzajú brány šablóny: ciele, ktoré `Makefile` naozaj má a ktoré zastavia či prestavia kontajnery alebo menia DB či index (napr. `stop`, `down`, `restart`, `rebuild`, `destroy`, `init`, `db-import`, `db-migrate`, `*-reset`, `*-baseline`, `fixtures`), navrhni do `ask` ako `Bash(make <cieľ>*)`.
- Cieľ: tím → `.claude/settings.json`; lokálne → vždy `.claude/settings.local.json` (ignorovanie over v kroku 8).
- Zlúčenie len pridáva, zachová poradie, nič nemaže, do `allow` nič nedáva (neexistujúci cieľ = `{}`):
  `jq -s '.[0] as $p | (.[1].permissions // {}) as $t | $p | .permissions.ask = (($p.permissions.ask // []) as $a | $a + (($t.ask // []) - $a)) | .permissions.deny = (($p.permissions.deny // []) as $d | $d + (($t.deny // []) - $d))' <cieľ> <vyplnená-šablóna>`
- Ukáž presný blok `permissions` pred → po, zapíš až po „áno".
- Do commitnutých settings nepridávaj `enabledPlugins` ani `extraKnownMarketplaces` (kolegovia marketplace kitu zatiaľ nemajú).
- Vendor kód v repe z kroku 1 navrhni so súhlasom do `deny` ukotvene ku koreňu: adresár `Edit(/<cesta>/**)`, vzor súborov `Edit(/www/js/**/*.min.js)`. Rovnaký zoznam použi pre `{{vendorFrontendPaths}}` v kroku 7.
- Heslo alebo token v existujúcich `allow` pravidlách len nahlás, needituj.

## 6. infer-conventions

- Hľadaj **nedefaultné, dobre podložené** konvencie: ≥ 3 výskyty v ≥ 2 súboroch, protipríklady ≤ 10 % (uveď počet). Legacy vs. nový kód (`git log --since=6.months --name-only`) sa líši → platí nový kód, povedz to.
- Oblasti: pomenovanie (triedy, testy, migrácie), DI (konštruktor vs. `inject*`), chyby (výnimky vs. návratové hodnoty), DB (parametre, model/repository), šablóny a JS kotvy, testy (base triedy, rollback, fixtures), commit správy (`git log --format=%s -50`).
- Preskoč: čo vymáha phpcs/PHPStan/rector/php-cs-fixer/ruff/mypy (prečítaj ich config), defaulty PSR-12 a frameworku, čo už je v `CLAUDE.md` alebo rules.
- Výstup: všetky konvencie, ktoré prešli filtrom, zoradené podľa sily dôkazu: `N. <konvencia ako pokyn> — dôkaz: a.php:12, b.php:40, c.php:7 (k/n)`.
- Schvaľuje sa po jednom (`áno 1,3`). Schválené → `.claude/rules/conventions.md`: `paths:` = globy pokrývajúce dôkazy, 1 pokyn = 1 riadok, ≤ 60 riadkov, bez hlavičky `dev-kit:`. Konvencie bez súborového rozsahu (commit správy) patria do `CLAUDE.md`.

## 7. CLAUDE.md (≤ 120 riadkov)

- Kostra `${CLAUDE_PLUGIN_ROOT}/templates/<stack>/CLAUDE.md.tmpl`: Projekt · Stack · Príkazy · Architektúra · Pravidlá · Pasce · 3 riadky pre kompakciu. Úvodný komentár šablóny `<!-- … -->` sú pokyny pre teba — do `CLAUDE.md` ho neprenášaj.
- **Overovací blok (V9):** ku každému príkazu tvar zdravého výstupu (`OK (… tests, … assertions)`, `[OK] No errors`) z reálneho behu v kroku 3 — bez presných počtov testov a časov, tie zastarávajú.
- **3 riadky pre kompakciu** zo šablóny ponechaj (zmenené súbory + stav `/dev:check` · otvorené rozhodnutia + ďalší krok · príkazy na overenie).
- `CLAUDE.md` neexistuje → vyplň kostru z detekcie.
- `CLAUDE.md` existuje:
  - tematické sekcie (frontend, DB, testy, API, doména) → `.claude/rules/projekt-<téma>.md` s `paths:` na súbory, ktorých sa týkajú;
  - pravidlo, ktorého strata spôsobí regresiu mimo jedného adresára → v CLAUDE.md ostane 1 riadok + odkaz (path-scoped rule sa načíta až pri práci so zhodným súborom);
  - zastarané príkazy a čísla oprav podľa krokov 1 a 3.
- Pred zápisom ukáž celý nový `CLAUDE.md`, `diff -u` a **mapu presunov** `CLAUDE.md:<od>-<do> „<sekcia>" → <cieľ>` + vypustené riadky s dôvodom. Každé pravidlo skončí práve na jednom mieste.
- Veľký prepis (> 30 % riadkov) len s výslovným súhlasom.
- **Lokálny režim a `CLAUDE.md` v gite → nerozsekávaj** (tím by o presunuté pravidlá prišiel, rules sú mimo gitu). Overovací blok a riadky kompakcie navrhni do `CLAUDE.local.md`.

## 8. Lokálne vs. tím

- **Lokálne** (voľba = súhlas, urob hneď po schválení plánu, pred krokom 3): do `"$(git rev-parse --git-common-dir)/info/exclude"` (spoločný pre všetky worktree) doplň chýbajúce riadky: vždy `.claude/worktrees/` (aj keď ešte žiadny worktree neexistuje) a pre nesledované súbory, ktoré init vytvorí: `.claude/devkit.json`, `.claude/rules/`, `.claude/skills/<meno>/`, `.claude/settings.local.json` (ak ho git ešte neignoruje — vytvorený nástrojom Write sa sám nevylúči), `.worktreeinclude`, `REVIEW.md`, `CLAUDE.local.md`, `*.pred-devkit`, nesledovaný `handoffDoc` (`docs/handoff.md` založí až `/dev:handoff`) a `docs/plans/` (plány z `/dev:plan` ostávajú lokálne — v lokálnom režime z kitu nič nejde do gitu). Over `git check-ignore -v <cesta>`. Už sledované súbory exclude neskryje — povedz to.
- **Lokálne, po krokoch 4–7:** do `.worktreeinclude` doplň `.claude/rules/`, `CLAUDE.local.md` a `REVIEW.md` — len tie, ktoré init vytvoril a vylúčil — a vždy `docs/plans/` (plán úlohy má byť aj vo worktree). `claude --worktree` ich inak nemá: z hlavného checkoutu sa čítajú len skills, agents a commands, a ignorovaný `CLAUDE.local.md` existuje len vo svojom checkoute. Súbor neexistuje → vytvor ho s hlavičkou `# dev-kit: <stack>/.worktreeinclude @ <VER>`. Nepridávaj `.claude/settings.local.json` (súhlasy sa čítajú z hlavného checkoutu), `.claude/skills/` (čítajú sa z hlavného checkoutu) ani `.claude/devkit.json` (skripty kitu siahnu po kópii v hlavnom checkoute).
- **Tím:** nič nevylučuj. Navrhni doplniť `.claude/worktrees/` do `.gitignore` (ukáž diff, zapíš len so súhlasom). Vypíš súbory na commit vrátane `.gitignore`, necommituj (ponúkni `/dev:commit`).

## 9. `--sync` (aktualizácia skopírovaných šablón)

1. Súbory s hlavičkou: `grep -rlE --exclude-dir=worktrees '^(<!--|#) dev-kit: ' .claude REVIEW.md .worktreeinclude 2>/dev/null || true` (chýbajúci súbor = exit 2, zoznam platí); z hlavičky `<cesta>` a starú verziu `OLD` (bez prípadného `v`).
2. Pre každý: `TEMPLATE` = `${CLAUDE_PLUGIN_ROOT}/templates/<cesta>`, `LOCAL` = súbor bez riadku hlavičky; `{{…}}` v šablónach vyplň rovnako ako v `LOCAL`.
   - šablóna zmizla → navrhni zmazanie (súhlas);
   - `LOCAL` == `TEMPLATE` → `= aktuálne` (len zdvihni verziu v hlavičke);
   - `BASE` = šablóna vo verzii `OLD`: `git -C "${CLAUDE_PLUGIN_ROOT}" show "dev--v<OLD>:./templates/<cesta>"` (funguje, keď je kit git repo s release tagmi);
   - s `BASE` → `git merge-file -p LOCAL BASE TEMPLATE` (lokálne úpravy ostanú); bez `BASE` → `diff -u LOCAL TEMPLATE` po blokoch: prevziať / ponechať.
3. Per súbor ukáž diff výsledku, zapíš až po súhlase, v hlavičke nastav `@ <VER>`. Konfliktné značky (`<<<<<<<`) nikdy nezapíš — vyrieš ich s používateľom.
4. Nové súbory šablóny, ktoré projekt nemá (rules, B-kusy) → ponúkni ako v kroku 4. Rovnako chýbajúce riadky z kroku 8 (režim: `.claude/devkit.json` v gite = tím, inak lokálne): `.claude/worktrees/`, nesledovaný `handoffDoc` a `docs/plans/` v `info/exclude` (lokálne) alebo `.claude/worktrees/` v `.gitignore` (tím, so súhlasom); lokálne `.claude/rules/`, `CLAUDE.local.md`, `REVIEW.md` (len existujúce a ignorované) a `docs/plans/` v `.worktreeinclude`.
5. `devkit.json` a settings (bez hlavičky): porovnaj `guards`, `pairs`, `check.steps` podľa `id` a `permissions.ask`/`deny` so šablónou; navrhni len **nové** položky, existujúce hodnoty nemeň.
6. Súhrn: tabuľka súbor · stav (aktualizované/aktuálne/konflikt/nové) · čo sa zmenilo.

## 10. Záver

- Vytvorené / zmenené: zoznam ciest.
- Commit: tím → zoznam na commit (`/dev:commit`) vrátane `.gitignore` s `.claude/worktrees/`; lokálne → „v `.git/info/exclude` (aj `.claude/worktrees/`), nič na commit“.
- Worktree: kam išiel `.claude/worktrees/` a ktoré riadky pribudli do `.worktreeinclude` (lokálne).
- Vrátenie: nové súbory `rm <cesty>`; sledované zmenené `git checkout -- <cesta>`; nesledované zmenené `mv <súbor>.pred-devkit <súbor>`. Po overení `*.pred-devkit` zmaž (nie sú na commit).
- Kedy platí: hooky čítajú `devkit.json` hneď; `CLAUDE.md` a rules po `/clear` alebo v novej session.
- Ďalší krok: jedna veta (napr. `/dev:check --full` ako východiskový stav integration testov).

## Pasce

- `make` ciele s `docker exec -it` bez TTY padnú → do `devkit.json` vždy priamy príkaz.
- Mená testsuite sú citlivé na veľkosť písmen (`unit` ≠ `Unit`).
- `docker compose config` zlyhá na chýbajúcom `.env` → čítaj YAML a cesty rieš relatívne k adresáru compose súboru.
- Kontajner mountuje len podadresár → worktree mapovanie nefunguje, `check.sh` kroky preskočí.
- `paths:` v rules sú relatívne ku koreňu projektu (adresár s `.claude/`).
