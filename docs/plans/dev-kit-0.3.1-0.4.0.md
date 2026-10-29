# dev kit 0.3.1 a 0.4.0 — opravy z analýzy a rozšírenia

- Vetva: `main` · Dátum: 2026-10-29 · Stav: schválený
- Zdroj: analýza stavu kitu z 2026-10-29 (review skriptov, skillov a šablón, novinky Claude Code 2.1.312, logy hookov) a rozhodnutia používateľa v tej istej session.

## Ako s týmto plánom pracovať

- Dve fázy = dve vydania. Fáza 1 (0.3.1) sú opravy bez zmeny kontraktu navonok; fáza 2 (0.4.0) mení `devkit.json` schému, šablóny a pridáva funkcie. Fázu 2 začni až keď je fáza 1 commitnutá a `make check` PASS.
- Každý bod má svoj commit (alebo skupinu príbuzných bodov), správa po slovensky `typ: výstih`. Nič nepushuj a netaguj; vydanie (`make release`, `claude plugin tag --push`) robí používateľ.
- Pri každej zmene skriptu alebo hooku v tom istom commite: prípad v `tests/selftest.sh` a úprava `docs/SPEC.md` (pravidlá 3 a 4 v `CLAUDE.md`). Zmena šablóny → záznam v `CHANGELOG.md` (pravidlo 9).
- Kit je nainštalovaný in-place: rozbitý skript hneď zasiahne všetky session. Po každom bode `bash tests/selftest.sh`, po skupine `make check`, zmenu hooku over aj v reálnej session cez `/reload-plugins`.
- Číslovanie bodov nižšie je vlastné (A1–A9 opravy, B1–B15 rozšírenia); v commitoch a odchýlkach sa odkazuj na tieto čísla. Mapa na zoznam z analýzy: opravy 1–6 → A1–A6; 7–10 → B1, B2; 11, 12, 18 → A7 a A5; 13, 17 → A8; 14, 15 → B3; 16 → A5; zlepšenia → B4–B14 a A9; B15 vznikol z R4. Nič zo zoznamu analýzy nie je vynechané; vedome odložené veci sú len v časti Mimo rozsahu.
- Rozhodnutia používateľa (nemeniť bez opýtania): R1 commit gate pri PARTIAL ďalej blokuje, ale vysvetlí a ponúkne únik (doplnené 2026-10-29: keď v PARTIAL behu neprešiel žiadny krok, únik je `disabledRules commitGate`; pri aspoň jednom ok kroku ostáva `step:<id>`); R2 `runtime: host` aj frontend lint idú do 0.4.0; R3 dôvera k `devkit.json` = upozorniť pri zmene, nebrániť; R4 (2026-10-29) A4 len minimálne (riadok v deny texte, bez rozvíjania premenných a bez prepisu parsera), parser príkazu commitu je samostatný bod B15 v 0.4.0.
- Rozhodnutia prijaté v pláne (meniť len s dôvodom zapísaným v Odchýlkach): verzie 0.3.1 + 0.4.0; `task-tldr` dostane generický príklad; Symfony ask pravidlá podľa Nette; Stop hook timeout 600 s; PreCompact hook áno; CI pre kit cez GitHub Actions; eval suite ako samostatný `make eval`, nie súčasť `make check`; `agentReadOnly` bez configu ostáva, len sa zdokumentuje.

## Úloha

- Po fáze 1 kolega s pluginom z marketplace nevidí údržbovú hlášku s cudzou cestou, Stop po commite v tom istom ťahu nehlási falošné pripomienky, commit gate pri PARTIAL vysvetlí príčinu a únik, nerozriešený `cd` je v deny texte pomenovaný, dokumentácia a kód sa zhodujú v počte blokov Stop (3×).
- Po fáze 2 šablóny troch stackov majú rovnaké guardy, ask pravidlá a zástupné symboly s pravidlom, čo s nevyplnenými; `devkit.json` pozná `runtime`; init pozná Nette Tester a phinx; kit má CI, eval suite a PreCompact hook; `check.sh` sa dá spustiť v CI projektu.
- Všade: `make check` PASS, `bash tests/selftest.sh` PASS, `make details` ≤ 3000 tokenov, selftest pod 20 s.

## Fáza 1 — 0.3.1 (opravy)

### A1 Údržbová hláška len pre checkout kitu
- `plugins/dev/scripts/session-card.sh:155–165`: hlášku „údržba kitu …“ (oba varianty) vypísať len keď existuje `"$DK_SCRIPTS/../../../tools/upstream.sh"` (teda plugin beží in-place z pracovnej kópie). Cestu v texte odvodiť z tej istej cesty (`make -C <koreň kitu> upstream`), nie natvrdo cesta z pracovnej kópie autora.
- SPEC §4.7 bod 6: doplniť podmienku a variant „ešte nebežala“.
- Selftest: karta v čistom `HOME` bez `tools/upstream.sh` vedľa skriptov nemá v `systemMessage` ani v karte slovo `údržba`; s podstrčeným `tools/upstream.sh` ho má.

### A2 Pairs po commite v tom istom ťahu
- `plugins/dev/scripts/lib.sh:474 dk_session_add`: pri prvom zápise do `sessions/<id>.files` uložiť aj `sessions/<id>.head` = `git rev-parse HEAD` (ak repo nemá HEAD, prázdny súbor); `*.head` pridať do upratovania starých session v `session-card.sh:203` vedľa `*.files`.
- `plugins/dev/scripts/stop-check.sh:50–60`: množina pre `unless` = `dk_changed_files` ∪ súbory session ∪ `git diff --name-only <head zo súboru> HEAD` (len keď `.head` existuje a líši sa od HEAD).
- SPEC §2 nový súbor `sessions/<session_id>.head`, §4.6 krok 2 nové znenie.
- Selftest: session s `app/Foo.php` + `tests/FooTest.php`, `git commit -a`, Stop → bez `[pair:…]`; kontrolný prípad bez testu → pripomienka ostáva.

### A3 Commit gate pri PARTIAL vysvetlí a dá únik (R1)
- `plugins/dev/scripts/check.sh`: pri verdikte PARTIAL zapísať `$DK_PDATA/partial.json` = `{"time":…, "mode":…, "ok":<počet ok krokov>, "steps":["unit", …], "lines":["! unit: kontajner app-php nebeží", …]}` (`lines` max 5 riadkov na zobrazenie, `steps` úplný zoznam id krokov s `!`); pri PASS v quick/full ho zmazať.
- `plugins/dev/scripts/pre-bash.sh:491–505`: keď gate zamieta pre chýbajúci PASS a existuje `partial.json` mladší ako 24 h, deny text má navyše riadok „posledná kontrola skončila PARTIAL:“ + jeho riadky a únik podľa `ok`: pri aspoň jednom ok kroku „navrhni používateľovi spustiť kontajner <c> (alebo odstrániť príčinu) a kontrolu zopakuj, alebo krok dočasne vypni: disabledRules step:<id> v .claude/devkit.json“ so všetkými id zo `steps`; pri `ok` = 0 „vypnutie krokov by dalo SKIP, nie PASS — navrhni používateľovi spustiť kontajner <c>, alebo gate dočasne vypni: disabledRules commitGate v .claude/devkit.json (kontrola tajomstiev aj Stop bežia ďalej)“. Vždy dodatok „(zapíš to používateľovi)“ a nikdy imperatív „spusti kontajner“ — skilly `check` a `commit` zakazujú Claudovi kontajnery štartovať. Záver „Spusti kontrolu: …“ ostáva.
- `CLAUDE.md` pravidlo 6: doplniť výslovnú výnimku „commit gate pri PARTIAL blokuje, hlásenie musí povedať prečo a ako ďalej“. SPEC §4.4 bod 2 a §4.5 (nový marker) upraviť.
- Selftest: krok s kontajnerom, ktorý nebeží (docker atrapa vracajúca false) → `check.sh` exit 4, `partial.json` existuje; následný `git commit` → deny obsahuje `PARTIAL` aj `disabledRules commitGate` (0 ok) a neobsahuje imperatív „spusti kontajner“; druhý prípad s jedným ok krokom a jedným blokovaným (atrapa s exit 127) → deny obsahuje `disabledRules step:<id>`; tretí prípad so 7 blokovanými krokmi → únik vymenuje všetkých 7 id.

### A4 Nerozriešený `cd` / `-C` v deny texte
- Rozsah zúžený rozhodnutím R4 (2026-10-29): žiadne rozvíjanie premenných z príkazu a žiadny prepis rozpoznávania `cd` — prvá verzia bodu (prepis parsera) priniesla v troch kolách overenia tri nové fail-open diery a bola zahodená. Existujúca logika `pre-bash.sh` (regexy `DK_RE_CD`, skladanie `cd`, nerozlúštiteľný `cd` = cwd session) ostáva, mení sa len text a dva okraje.
- `plugins/dev/scripts/pre-bash.sh`: keď cieľ `cd` alebo `git -C`/`--work-tree`/`--git-dir` ostane nerozriešený (premenná, `$(…)`, spätný apostrof, `~iný`), do deny textu pridať riadok „cieľ `cd`/`git -C` sa nedal určiť (<úryvok do 60 znakov>) — použi doslovnú cestu“; `cd "$(pwd)"` a `cd $PWD` = aktuálna báza; `cd` preskočí prepínače `-L`/`-P` a jedno `--` za nimi a berie prvé ďalšie slovo; iné slovo s `-` na mieste cieľa (`-e`, `-@`, prepínač za `--`) je nerozriešené, lebo bash 3.2 a zsh ho odmietnu a shell ostane na mieste. Správanie fail closed ostáva bez zmeny.
- SPEC §4.4 odsek Repo: doplniť riadok deny textu a prepínače `cd`; do odseku Známe obmedzenia (vedľa `sh -c`) zapísať diery, ktoré overenie našlo už v pôvodnom kóde a rieši ich až B15: `false && cd <x>; git commit` (cd za `&&`/`||` nasledované `;` sa berie ako vykonaný), `HOME=<x>; cd ~`, `X=1 cd <x>`, `\cd`, `pushd`, `case … ) cd <x>;; esac`, `echo "; cd /x"`, `cd /x & git commit`, `X=$(cd /x; pwd)`.
- Selftest: `git -C <iné repo bez devkit.json> commit` → allow (dnes chýba prípad); `cd "$(nieco)" && git commit` → deny obsahuje „sa nedal určiť“ a úryvok; `cd "$D" && git commit` s `D=` v tom istom príkaze → deny v cwd session s riadkom „sa nedal určiť“ (premenné sa nerozvíjajú); `cd -- <iné repo bez configu> && git commit` a `cd -P …` → allow.

### A5 Stop timeout a stop mód
- `plugins/dev/hooks/hooks.json`: Stop `timeout` 600. SPEC §4 JSON.
- Šablóny `php-nette/devkit.json`, `php-symfony/devkit.json:26`, `python/devkit.json`: v režime `stop` len rýchle kroky (unit bez integračných: Symfony `--exclude-group integration` alebo `--testsuite unit` ak existuje, poznámka v `_init`, že init vyberie podľa `phpunit.xml`). CHANGELOG.
- `plugins/dev/scripts/stop-check.sh:123–131`: pri zhode hashu s posledným FAIL (fails 1–2) nespúšťať `check.sh` znova, zablokovať z uloženého dôvodu (`stop.json` dostane pole `reason`, ≤ 20 riadkov). SPEC §4.6 krok 3 a §4.5 tvar `stop.json`. Selftest: druhý Stop s rovnakým obsahom nespustí krok (atrapa nástroja zapíše značku, značka sa nesmie objaviť druhýkrát).

### A6 Rozpor 2× vs 3×
- `plugins/dev/skills/check/SKILL.md:62` a hlavička `plugins/dev/scripts/stop-check.sh:3`: „najviac 3×“. Over, že README riadok 30 a SPEC §4.6 bod 5 hovoria to isté.

### A7 Drobné opravy skriptov (jeden commit)
- `stop-check.sh:133–135`: exit 3 alebo ≥ 5 z `check.sh` → `dk_log … skip` + pripomienka `[dev-kit] kontrola sa nedala spustiť (exit N) — pozri errors.log`, nie `pass`.
- `lib.sh:436–455 dk_blobs`: pri nenulovom exite `git hash-object --stdin-paths` hashovať súbory po jednom; nečitateľný súbor = `-` a `dk_err`. Symlink s kódovou príponou vynechať zo sady (aj v `pre-bash.sh:342`).
- `lib.sh:50–60 dk_data_dir`: `(umask 077; mkdir -p "$d")` namiesto `mkdir -p` + `chmod`.
- `lib.sh:61 dk_err`: rotácia `errors.log` nad 1 MB (ponechať posledných 500 riadkov), rovnako ako `decisions.jsonl` v `session-card.sh:205`.
- `lib.sh:331`, `on-edit.sh:42`: stav kontajnera cachovať v `$DK_PDATA/container.state` (`<epoch> <running|down>`), platnosť 30 s; `check.sh` cache ignoruje.
- `check.sh:199–202`: krok bez `ext` s `runFiles` dostane do `{files}` len kódové súbory (`dk_is_code`); SPEC §4.5.
- `lib.sh:534`, `check.sh:255`, `on-edit.sh:67`: cesty do `awk` cez `ENVIRON`, nie `-v` (spätné lomky).
- `check.sh:88–99`: keď `fullWhen` zasiahne a žiadny krok nie je len pre `full`, vypísať riadok `– full: rovnaké kroky ako quick`.
- Každá zmena má riadok v SPEC a prípad v selfteste tam, kde sa dá bez dockeru (cache kontajnera cez atrapu `docker` na PATH).

### A9 Medzery selftestu bez zmeny kódu
- Pridať prípady pre správanie, ktoré skripty už majú, ale test ho nekryje: pytest riadok `FAILED tests/test_x.py::test_y` v `knownFailures` (krok nie je FAIL, súhrn má `známe`); predvolené vzory tajomstiev `AKIA[0-9A-Z]{16}` a `-----BEGIN … PRIVATE KEY-----` v on-edit aj v commit gate (hodnota maskovaná `****`); `testRemoved` pri zmazaní celého test súboru (dnes len metóda); `commitGate.enabled: false` a `disabledRules: ["commitGate"]` pri stále aktívnej kontrole tajomstiev.
- Ak niektorý prípad odhalí chybu, oprav skript (nie test) a zapíš to do Odchýlok.

### A8 Dokumentácia a SPEC
- `docs/SPEC.md:1,41`: verzia podľa `plugin.json`; §0 riadky 7, 11, 18 a §5 riadky 407–415, 430: osobné cesty nahradiť neutrálnymi (`<KIT>`, „používateľove pôvodné príkazy“); §1 riadok 54 „No LICENSE“ zmazať (repo má MIT `LICENSE`); klon ECC v `README.md:84`, SPEC riadok 538 a `plugins/dev/PROVENANCE.md:3` uvádzať ako `ECC_DIR` s predvolenou hodnotou `<KIT>/../ECC` a tú istú predvolenú hodnotu dať do `tools/upstream.sh:7` (odvodenú od umiestnenia skriptu, nie od `$HOME`); §4.7 doplniť podpríkaz `session-card.sh --record-handoff <path> <title>`; §3/§4.3 zapísať výnimku `agentReadOnly` (platí aj bez `devkit.json`, vstupné pole `agent_type`).
- `README.md:41`: `/dev:check [--quick · --full · --auto] [--files …]`.
- `CHANGELOG.md`: sekcia `## 0.3.1 — <dátum>` s bodmi A1–A9.

## Fáza 2 — 0.4.0 (šablóny, schéma, funkcie)

### B1 Verejné repo: generické príklady
- `plugins/dev/skills/task-tldr/SKILL.md:37–62`: príklad prepísať na generickú doménu (napr. e-shop: nové stavy objednávky, skrytie zrušených produktov v exporte, krok po nasadení) pri zachovaní tvaru „dobrý výstup / zlý výstup“. SPEC §5 riadok 430: zrušiť klauzulu „byte-identical copy“.
- `plugins/dev/skills/ecc-change-impact/SKILL.md:24`: „iná škola/firma“ → „iný tenant“.
- Prejdi `grep -rn` na rezortné skratky a `.test-credentials`-špecifiká: `debug/SKILL.md:49–51` (Mailpit, Typesense, `.test-credentials`) a `php-nette/rules/tests.md:14,40`, `php-nette/CLAUDE.md.tmpl:54,86` formulovať podmienečne („ak projekt má službu `mailpit` v compose…“) alebo cez symbol `{{testCredentialsFile}}`.

### B2 Zjednotenie šablón (Nette ↔ Symfony ↔ Python)
- `php-nette/CLAUDE.md.tmpl:33–42`: zaviesť `{{run}}` ako v `php-symfony/CLAUDE.md.tmpl:9` (prázdne pri `container: ""`); značky `<!-- db:… -->` presunúť pred posledný `|` alebo do pokynu initu „zmaž ` | <!-- … -->` celé“; riadok 83 pri prázdnom `{{vendorFrontendPaths}}` bez zátvorky.
- `php-nette/devkit.json`: guard `dql-concat` ako položka `doctrine-*` (vzor z `php-symfony/devkit.json:45`); guardy `die` (:48) a `debug-php` (:44) prevziať zo Symfony (`(^|[^>:$_[:alnum:]])…`), `bdump` ponechať; pair `model-test` (:60) rozšíriť na `app/model/**`, `app/Model/**` ako `fullWhen` (:39).
- `php-symfony/settings.json:13–16` + `php-symfony/CLAUDE.md.tmpl:35`: ask pravidlá na Doctrine podľa `php-nette/settings.json:13–25` (migrate aj `--dry-run`, diff, schema:update, dbal:run-sql); `migrations:migrate` vyhodiť z tabuľky bežných príkazov. SPEC §7 veta o „12 ask rules intended“ upraviť.
- Baseline politika: jedno znenie v `php-nette/rules/php-core.md:16`, `php-nette/CLAUDE.md.tmpl:23`, `php-symfony/rules/php-core.md:18`, `php-symfony/CLAUDE.md.tmpl:77`: „nový nález oprav v kóde; baseline sa regeneruje len na pokyn používateľa“.
- Dibi: „Dibi 4+“ všade (`db-dibi.md:12`, `php-nette/CLAUDE.md.tmpl:95`, `review/SKILL.md:43`, `ecc-silent-failure-hunter.md:52–53`; `ecc-mysql-patterns:126` znenie už má).
- `ecc-mysql-patterns/SKILL.md` `paths:` doplniť `**/Entity/**`, `**/Repository/**`.
- `php-symfony/.worktreeinclude`: druhý vysvetľujúci riadok ako ostatné stacky.
- `python/rules/tests.md:12`, `ecc-python-testing/SKILL.md:94`: „podľa kroku `unit` v devkit.json“.
- `hooks.json`: `NotebookEdit` pridať do matcherov PreToolUse a PostToolUse (edit notebooku v Python stacku dnes obíde lint aj guardy); SPEC §4.
- CHANGELOG za každú šablónu; selftest pre nové vzory guardov (`->exit(` a `$this->dump(` nechytí, `die(` a `exit;` chytí; `dql-concat` chytí `->where('a = ' . $x)`).

### B3 Zástupné symboly a fázy súhlasu v `project-init`
- Zjednotiť mená: `{{entityGlob}}`/`{{migrationsGlob}}` (`php-nette/devkit.json:5,62`) vs `{{entityDir}}`/`{{migrationsDir}}` (`CLAUDE.md.tmpl:21,62,65`) → jeden názov pre jednu vec vo všetkých troch stackoch; `dbContainer` (`SKILL.md:37`) označiť ako textový symbol, nie pole schémy.
- `plugins/dev/skills/project-init/SKILL.md` krok 7: tabuľka symbol → zdroj detekcie pre všetky symboly šablón (33 Nette, 25 Python, 9 Symfony; vypíš ich `grep -o '{{[a-zA-Z]*}}' | sort -u`); pravidlo: detekovateľné vyplň, nedetekovateľný riadok zmaž bez otázky, pýtaj sa len na `projectDescription`, `commitStyle` (ak nie je v git logu) a kontajner (ak compose chýba). Limit otázok ostáva 4.
- Fázy súhlasu pomenovať výslovne: 1 plán (dry-run + permissions + lokálne/tím), 2 zápis + overenie `check.sh --quick`, 3 konvencie, 4 `CLAUDE.md`/`AGENTS.md` diff; kroky 5 a 8 zlúčiť do fázy 1.
- Lokálny režim: nový `CLAUDE.md` nevytvárať; projektový obsah ide do `CLAUDE.local.md` (krok 139, zoznam exclude na 150 doplniť o `CLAUDE.local.md`). SPEC §6 bod 7.
- `SKILL.md:82`: `--project "${CLAUDE_PROJECT_DIR}"` ako ostatné skilly. Popis skillu skrátiť pod 250 znakov (`SKILL.md:3`).
- Init bez compose (`container: ""`): v dry-run povedať, že kroky bežia na hostiteľovi, `appRoot` sa nepoužije, a overiť nástroje cez `command -v` / `vendor/bin`.

### B4 `runtime: host | container` (R2)
- Schéma (SPEC §3): krok `check.steps[]` dostane voliteľné `runtime` (`"container"` predvolene keď je `container` nastavený, inak `"host"`); položka `lint` mapy môže byť reťazec alebo objekt `{"run": "<cmd>", "runtime": "host"}`.
- `lib.sh:338 dk_exec` dostane druhý parameter `runtime`; `host` = `(cd "$DK_PROJECT" && sh -c "$cmd")` aj keď je kontajner nastavený; `{file}`/`{files}` sú relatívne k projektu v oboch prípadoch. `check.sh` (kroky) a `on-edit.sh:21–55` (lint objekty) to rešpektujú; krok s `runtime: host` nepodlieha `dk_container_ok` ani `dk_workdir`.
- `requires` pri `host` sa kontroluje tiež na hostiteľovi (ako dnes).
- Selftest: krok `runtime: host` s nastaveným `container` a atrapou `docker`, ktorá vždy zlyhá → krok beží a PASS; lint objekt s `runtime: host` → beží.
- `session-card.sh`: riadok karty ukazuje `kontajner <c> (NEBEŽÍ …)` len ak existuje aspoň jeden kontajnerový krok.

### B5 Frontend lint (R2)
- Šablóny `php-nette` a `php-symfony`: voliteľný krok `frontend` (`runtime: host`, `requires: node_modules/.bin/eslint`, `runFiles: node_modules/.bin/eslint {files}`, `ext: [".js", ".ts"]`, modes quick/full) a `stylelint` pre `.css`/`.scss`; guardy `console-log` (`console\.(log|debug)\(`, ext `.js`, `.ts`) a `inner-html` (`\.innerHTML[[:space:]]*=`); `commitGate.ext` o `.js`, `.ts`, `.css`, `.scss`. `_init` poznámka: init pridá len keď projekt má `package.json` s eslint/stylelint.
- `project-init/SKILL.md` detekcia: `package.json` → eslint, stylelint, ich konfigy; bez nich krok vynechať bez otázky.
- `latte-frontend.md` a `twig-frontend.md`: odkaz na guardy. CHANGELOG, selftest pre guardy.

### B6 Dôvera k `devkit.json` (R3)
- `lib.sh dk_init`: hash `devkit.json` (`git hash-object`) porovnať s `$DK_PDATA/config.hash`; pri rozdiele nastaviť `DK_CFG_CHANGED=1` a hash prepísať.
- `session-card.sh`: pri zmene riadok karty `devkit.json sa zmenil od poslednej session: <N> príkazov (lint/kroky) — skontroluj diff` + `systemMessage`; `on-edit.sh` a `pre-bash.sh`: pri `DK_CFG_CHANGED=1` jednorazovo (per session, značka `sessions/<id>.cfgnote`) vypísať na stderr riadok `[dev-kit] devkit.json sa zmenil — príkazy: <zoznam run/lint, ktoré sa líšia>`. Hooky bežia ďalej (nebrániť). `*.cfgnote` pridať do upratovania v `session-card.sh:203`.
- Zoznam zmenených príkazov: porovnanie `jq '[.lint, .check.steps[].run, .check.steps[].runFiles]'` so snapshotom `$DK_PDATA/config.cmds.json`.
- README sekcia „Keď hook otravuje“ alebo nová veta pri tímovom režime; SPEC §2 nové súbory, §4.1, §4.2, §4.7. Selftest: zmena `run` v configu → karta obsahuje „sa zmenil“, druhý štart už nie.

### B7 Nette Tester
- `project-init/SKILL.md:40`: detekcia `vendor/bin/tester` + `tests/*.phpt`; `php-nette/devkit.json`: alternatívny krok `tester` (`run: php vendor/bin/tester tests -s -C`, `_init`: použiť namiesto `unit`/`integration`, keď projekt nemá PHPUnit).
- `check.sh` `knownFailures`: identifikátory aj z riadkov Nette Testeru `^-- FAILED: <cesta>` (id = cesta). SPEC §3 odsek knownFailures. Fixture `tests/fixtures/real/tester-failed.txt` (vyrob syntetický výstup podľa dokumentácie Testeru, bez reálnych dát) + selftest.
- `test/SKILL.md:3` sľub Testeru ostáva pravdivý; `review/SKILL.md` checklist Nette spomenie Tester.

### B8 phinx
- `project-init/SKILL.md:40`: detekcia `vendor/bin/phinx` + `phinx.php|phinx.yml|phinx.json`; `migrations.paths` z `paths.migrations` (phinx.php parsuj regexom, nespúšťaj ho — je to kód projektu s autoloadom a prípadným pripojením k DB; pri neúspechu sa opýtaj v rámci limitu 4 otázok). `php-nette/devkit.json` `_init` poznámka. `db-dibi.md` už Phinx spomína, over znenie.

### B9 `check.sh` v CI projektu
- Nová sekcia README „CI“: ukážka GitHub Actions a GitLab CI, ktorá nainštaluje plugin (`claude plugin marketplace add` nie je potrebné: `git clone` kitu + `bash <kit>/plugins/dev/scripts/check.sh --full --project .`), s `container: ""` variantom cez `DEVKIT_CONFIG` override.
- `check.sh`: nový prepínač `--config <súbor>` (alebo premenná `DEVKIT_CONFIG`), ktorý nahradí `.claude/devkit.json` (CI bez kontajnera použije kópiu s `container: ""`); exit kódy už CI vyhovujú (0/1/3/4). SPEC §4.5. Selftest: `--config` s iným súborom.

### B10 CI pre kit samotný
- `.github/workflows/check.yml`: matrix `ubuntu-latest`, `macos-latest`; kroky: `jq` (apt/brew), `npm i -g @anthropic-ai/claude-code`, `make check`; ak `claude plugin validate` alebo `tools/details.sh` v CI bez prihlásenia zlyhá, spusť v CI `make selftest` povinne a `make validate`/`make details` ako `continue-on-error` s poznámkou v README. Spúšťať na push do `main` a na PR.
- README sekcia Vývoj kitu: odkaz na CI, badge nie je potrebný.

### B11 Eval suite skillov
- `plugins/dev/evals/<case>/prompt.md` + `graders/*.md` pre štyri prípady: `/dev:check` hlási PARTIAL pri exit 4 a nikdy netvrdí PASS; `/dev:commit` nikdy nepridá Co-Authored-By ani nepushne; `/dev:review` vypíše nálezy v predpísanom formáte s `súbor:riadok`; `/dev:fix` napíše padajúci repro test, zamkne ho cez `test-lock.sh` a opraví kód bez zmeny testu. Gradery `regex` + `tool_used` + `llm`. Prípady bežia nad syntetickým fixture projektom v `evals/fixtures/` (bez reálnych dát).
- `Makefile`: cieľ `eval` (`claude plugin eval plugins/dev --json --ablation with-without`), `make help` riadok; nie je súčasťou `make check` (stojí tokeny). `.gitignore` už má `**/evals/results/`. README Údržba: kedy spúšťať (pred vydaním) a čo znamená výsledok ablácie.
- Načítaj dokumentáciu `plugin-evals.md` pred písaním; formát suite over cez `claude plugin eval --help`.

### B12 PreCompact hook
- `hooks.json`: `PreCompact` → `scripts/pre-compact.sh`, timeout 10. Skript bez configu exit 0; s configom vypíše `additionalContext` (≤ 10 riadkov, fakty, nie imperatívy): súbory session (max 8), posledný výsledok zo `sessions/<id>.stop.json` (PASS/PARTIAL/FAIL + čas), aktívny zámok testu, posledný `pass.json` (mode, čas) a cesta handoff dokumentu. Over v `hooks.md` presný tvar výstupu pre PreCompact (`hookSpecificOutput.hookEventName: "PreCompact"`) a či `additionalContext` podporuje; ak nie, použiť `systemMessage` a zapísať do SPEC.
- SPEC §4 JSON + nová §4.10; `make details` ostáva ≤ 3000; selftest tvaru JSON.

### B13 Hook pole `if` a menšie využitie noviniek Claude Code
- `hooks.json`: PreToolUse/PostToolUse pre Edit|Write|MultiEdit|NotebookEdit doplniť `if` tak, aby skripty bežali len pre súbory s príponami, ktoré kit pozná, len ak dokumentácia `hooks.md` potvrdí syntax pre plugin hooks a že `if` nevyraďuje `devkit.json` s neznámou príponou (lint mapa je projektová, takže `if` smie obsahovať len univerzálne pravidlo, napr. vylúčiť `*.lock`, `*.min.js`, obrázky). Ak to nejde bezpečne, bod vynechať a zapísať do Odchýlok.
- `additionalContext` všade pod 10 000 znakov a bez imperatívov (prejdi `stop-check.sh`, `session-card.sh`, `pre-compact.sh`).
- Fakty o Claude Code, ktoré treba overiť v dokumentácii a zapísať do SPEC §0 ako predpoklady (bez zmeny kódu, ak platia): pluginové `settings.json` ignoruje `permissions` (šablóny ostávajú v projekte); pluginové agenty ignorujú `hooks`, `mcpServers`, `permissionMode`; Stop hook podporuje `hookSpecificOutput.additionalContext`; pole `if` nefunguje na Stop; `MultiEdit` je stále platný názov nástroja (ak nie, z matcherov ho vyhodiť); `CLAUDE_PLUGIN_DATA` existuje len pre hooky, nie pre Bash tool (ostáva `DEVKIT_DATA`). Čo neplatí, oprav a zapíš do Odchýlok.

### B14 Krok `audit` (composer audit, pip-audit)
- Šablóny: krok `audit` len v režime `full` — `php-*`: `requires: composer.json`, `run: composer audit --no-interaction --format=plain` (`runtime: host`, keď kontajner composer nemá; init overí `command -v composer` v kontajneri aj na hostiteľovi); `python`: `requires: pyproject.toml|requirements.txt`, `run: pip-audit` (alebo `{{bin}}pip-audit`), `requires` na binárku. Výstup bez čísel riadkov → `changedLinesOnly` vynechať; `knownFailures` môže ignorovať známe CVE podľa identifikátora (`^(PKSA|CVE|GHSA)-[A-Za-z0-9-]+`, doplniť do parsera identifikátorov v `check.sh`, SPEC §3).
- Súhlas: `composer audit` a `pip-audit` posielajú zoznam balíkov na Packagist alebo PyPI. Init krok zaradí len po súhlase, ktorý je súčasťou schválenia plánu (fáza 1 súhlasov v B3), nie samostatná otázka; `_init` poznámka v šablónach to hovorí. Bez súhlasu krok vynechať.
- `ecc-production-audit/SKILL.md` a `review/SKILL.md:113`: odkázať na krok namiesto vlastného spúšťania. CHANGELOG, fixture syntetického výstupu `composer audit` a `pip-audit` s jedným nálezom + selftest (FAIL, potom `známe` cez `knownFailures`).

### B15 Parser príkazu commitu (R4)
- Cieľ: jedna funkcia v `pre-bash.sh` (alebo samostatný `scripts/cmd-parse.sh` so spoločným `lib.sh`), ktorá z textu Bash príkazu vráti pre každý `git commit` dvojicu (báza, nerozriešené ciele) podľa pravidiel zapísaných v SPEC: maskovanie úvodzoviek, komentárov, `$(…)`, `<(…)`, spätných apostrofov a escapov; `cd` len na začiatku jednoduchého príkazu; `cd`/priradenie za `&&`/`||` (aj cez nový riadok, `\`+nový riadok, komentár) je nerozriešené; priradenie platí len na začiatku príkazu bez operátora pred ním; subshell, rúra, zoznam na pozadí, telo funkcie a `case` vetva = nerozriešené; commit vnútri `$(…)`/`<(…)` sa vyhodnotí s `cd` z tej istej substitúcie; `pushd`, `\cd`, `X=1 cd`, `HOME=…; cd ~` pokryté alebo výslovne nerozriešené.
- Návrh (pravidlá + tabuľka vstup → výstup) najprv do SPEC a na schválenie; implementácia až po ňom. Dôkaz: tabuľka ako fixture `tests/fixtures/cmd-parse.tsv` (vstup, očakávaná báza, očakávané riadky), selftest ju celú prejde; druhý fixture s prípadmi, ktoré musia byť fail closed (každý s commitom tajomstva → deny). Mutačný test: s `pre-bash.sh` z 0.3.1 musí padať aspoň polovica riadkov.
- Známe obmedzenia zo SPEC (zapísané v A4) po dokončení z odseku vymazať; `sh -c '…git commit…'` ostáva mimo.

- `CHANGELOG.md`: sekcia `## 0.4.0 — <dátum>` s B1–B15; `README.md` a `CLAUDE.md` kitu podľa pravidla 13.

## Súbory

- `plugins/dev/scripts/{lib,check,pre-bash,stop-check,session-card,on-edit}.sh`, nový `pre-compact.sh` — body A1–A7, B4, B6, B7, B9, B12
- `tools/upstream.sh` — A8
- `plugins/dev/hooks/hooks.json` — A5, B2, B12, B13
- `plugins/dev/skills/{check,task-tldr,ecc-change-impact,debug,project-init,test,review,ecc-mysql-patterns,ecc-python-testing,ecc-production-audit}/SKILL.md` — A6, B1, B2, B3, B7, B8, B14
- `plugins/dev/templates/{php-nette,php-symfony,python}/**` — A5, B1, B2, B3, B5, B7, B8
- `plugins/dev/agents/ecc-silent-failure-hunter.md` — B2 (Dibi)
- `plugins/dev/evals/**`, `Makefile`, `.github/workflows/check.yml` — B10, B11
- `docs/SPEC.md`, `README.md`, `CHANGELOG.md`, `CLAUDE.md`, `tests/selftest.sh`, `tests/fixtures/**` — priebežne

## Poradie

1. Fáza 1 v poradí A1, A2, A3, A4, A5, A6, A7, A9, A8; po každom bode `bash tests/selftest.sh`, po A8 `make check` a reálna session (`/reload-plugins`, jeden edit `.sh` súboru, jeden Stop, jeden pokus o commit bez PASS). Potom `/dev:handoff` a počkať na používateľa (vydanie 0.3.1).
2. Fáza 2: B1, B2, B3 (šablóny a skilly), potom B4, B5, B6 (skripty a schéma), potom B7, B8, B14, B9 (init, audit a CI projektu), potom B10, B11, B12, B13, nakoniec B15 (najprv návrh v SPEC na schválenie). Po každej skupine `make check` a `/dev:handoff`.
3. Pred koncom fázy 2 dry-run `/dev:project-init --dry-run` na syntetickom Nette + Doctrine projekte bez compose a na Symfony projekte s `package.json` (subagent, mimo repa kitu), výsledok do handoffu.

## Riziká

- Rozbitý skript zasiahne všetky bežiace session (in-place inštalácia) — po každom bode selftest, `bash -n` beží v on-edit automaticky; pri páde `/reload-plugins` až po zelenom selfteste.
- `runtime: host` mení exec cestu v `check.sh` aj `on-edit.sh` — selftest s atrapou `docker`, ktorá vždy zlyhá, musí dokázať, že host krok beží nezávisle.
- Zmena tvaru `lint` mapy (reťazec alebo objekt) — staré configy musia fungovať bez zmeny; selftest s pôvodným tvarom ostáva.
- `if` v plugin hooks a `PreCompact` výstup — syntax over v dokumentácii, nie z pamäte; pri nejasnosti bod vynechaj a zapíš.
- Zväčšenie always-on kontextu novým hookom a skillmi — `make details` po každom bode fázy 2.
- Selftest nad 20 s po pridaní prípadov — nové prípady drž v subshell paralelizme, atrapy bez `sleep`.
- CI na macOS runneri nemusí mať `claude` bez prihlásenia — povinný je len `make selftest`.

## Dôkaz

- `make check` → `[dev-kit] make check: PASS`; `bash tests/selftest.sh` → `PASS N/N`, N ≥ 107 + počet nových prípadov; `make details` → `always-on ~… ≤ 3000`.
- Nové prípady selftestu (minimálne): karta bez `tools/upstream.sh`; pairs po commite; `partial.json` + deny text; `git -C <iné repo>` allow; nerozriešený `cd` v deny; opakovaný Stop bez druhého behu; exit 3 → skip; `dk_blobs` s nečitateľným súborom; cache kontajnera; pytest `FAILED` v `knownFailures`; vzory AKIA a PRIVATE KEY; zmazaný celý test súbor; gate vypnutý so živými tajomstvami; guardy `die`/`debug-php`/`dql-concat`/`console-log`; `runtime: host` krok aj lint; zmena `devkit.json` → hláška raz; `knownFailures` z Tester výstupu a z `audit` výstupu; `check.sh --config`; PreCompact JSON.
- Reálna session po fáze 1 a po fáze 2: `/reload-plugins`, edit `.sh` → lint beží; Stop → žiadny falošný pair po commite; commit bez PASS → deny s novým textom.
- `claude plugin validate --strict plugins/dev` a `.` → `✔ Validation passed`.

## Mimo rozsahu

- Codex adaptér a „spoločné jadro“ (rozhodnuté skôr: nie).
- Nové stacky (Laravel, Node) — len na požiadavku kolegov.
- Allowlist príkazov v `devkit.json` (silnejší model dôvery ako R3).
- Spustenie eval suite v CI (tokeny).

## Odchýlky

- A1: koreň kitu sa určuje fyzicky (`cd -P "$DK_SCRIPTS/../../.." && pwd`) a test je `[ -f "<koreň>/tools/upstream.sh" ]` — rovnaká podmienka ako v texte, ale cesta v hláške sedí aj pri symlinkovanom adresári pluginu.
- A1: `t_card_stack_maintenance` dostal len prípravu `kit_scripts upstream` (asserty bez zmeny); bez nej by pri `DK_SELFTEST_SCRIPTS=<nainštalovaný plugin>` padal, hoci skript je správny.
- A1: `README.md` sekcia Údržba — veta o pripomienke karty doplnená o „len keď plugin beží z pracovnej kópie kitu“ (pravidlo 13).
- A2: diff commitov ide cez `git diff --name-only --no-renames <.head> HEAD` (ako `dk_changed_files`), aby premenovaný test dal do množiny `unless` starú aj novú cestu; logika je v novej funkcii `dk_session_committed` v `lib.sh`.
- A2: selftest `t_stop_pair_after_commit` má tri session: test editovaný cez Edit a commitnutý, test zmenený len cez Bash a commitnutý (overí `.head`), kontrolná bez testu.
- A3: `partial.json` píše len quick/full (aj s `--files`); Stop režim ho nepíše ani nemaže, má vlastný `stop.json`. Maže ho každý iný verdikt quick/full (PASS, FAIL, SKIP), nielen PASS, aby „posledná kontrola“ v deny texte sedela.
- A3: príčina v úniku je `spustiť kontajner <c>` len keď riadok hovorí `kontajner <c> nebeží` pre kontajner z configu, inak `odstrániť príčinu` (plán ich dáva naraz: „spustiť kontajner <c> (alebo odstrániť príčinu)“); za ňou v oboch variantoch `a kontrolu zopakuj`. Viac krokov = `kroky … disabledRules step:a, step:b`. Vysvetlenie sa pridá pri každom zamietnutí, ktoré žiada kontrolu (aj `fullWhen` → `--full`).
- A3: README (veta pod tabuľkou hookov) a `REVIEW.md` (projektová kontrola blokovania) doplnené o výnimku (pravidlo 13).
- A3: rozhodnutie používateľa po overení bodu: pri `ok` = 0 únik `disabledRules commitGate` namiesto `step:<id>` — vypnutie všetkých blokovaných krokov dá SKIP (exit 4), ten partial.json zmaže a gate by blokoval ďalej bez vysvetlenia; R1 a odrážky A3 doplnené. `ok` v `partial.json` = kroky ok + známe (`NOK + NKNOWN`), lebo aj známe zlyhania dávajú PASS. `CLAUDE.md` pravidlo 6 ostáva, znenie výnimky platí aj pre nový únik.
- A3: selftest `t_bash_commit_partial_explained` používa existujúcu atrapu `docker` (inspect bez `DK_FAKE_DOCKER_RUNNING` = kontajner nebeží), 0 ok → `commitGate` a ten commit naozaj pustí; `t_bash_commit_partial_one_ok` (nahradil `t_bash_commit_partial_stale_cleared`): `unit` ok + exit 127 → `step:tests`, `partial.json` starší ako 24 h sa nespomenie, po `disabledRules step:tests` PASS zmaže `partial.json` a commit prejde; `t_bash_commit_partial_all_ids`: 1 ok + 7 blokovaných → 5 riadkov, únik so všetkými 7 id.
- A4: zúžený podľa R4, parser odložený do B15; úryvok v riadku deny textu má tvar `cd|-C|--work-tree|--git-dir <cieľ>`, neskorší absolútny cieľ riadok zruší, `` `pwd` `` = báza ako `$(pwd)` a `~iný` je nerozriešený. Oprava po overení: prvé znenie plánu kázalo preskakovať aj `-e` a `-@`, ktoré bash 3.2 ani zsh nepoznajú (shell ostane na mieste, commit by bežal v cwd session bez kontroly) — preskakujú sa len `-L`, `-P` a jedno `--` za nimi, ostatné prepínače (aj za `--`) sú nerozriešené; shelly, ktoré ďalšie prepínače poznajú (zsh `-q`, bash ≥ 4.3 `-e`), sú zapísané v SPEC ako známe obmedzenie.
- A5: kľúč opakovania z uloženého dôvodu je okrem hashu súborov session aj `ctx` (blob hash `devkit.json`, HEAD a blobov `dk_changed_files`); bez neho by oprava mimo súborov session (`.neon`, zmena cez Bash) alebo `knownFailures`/`disabledRules`, ktoré blok sám navrhuje, zablokovali falošne ešte raz. `stop.json` má okrem `reason` aj `log` a `ctx`; `reason` = text bloku bez hlavičky a riadku `log:` (≤ 18 riadkov), hlavička sa skladá nanovo s počítadlom a dovetkom „výsledok predošlej kontroly — súbory session sa nezmenili“; pripomienky nové v tomto Stope idú pred uložený dôvod. `stop.json` bez `reason`/`ctx` (staršia verzia) kontrolu spustí.
- A5: `t_stop_fixed_then_fast` modeloval opravu len zmazaním ignorovanej značky `.marks/fail-unit` (bez zmeny súborov session aj pracovného stromu) — podľa A5 je to práve prípad, keď sa kontrola neopakuje, takže test odporoval plánu; oprava teraz mení aj `app/Foo.php`, asserty ostali.
- A5: šablóny `php-nette` a `python` už v stop púšťali len rýchle kroky (`--testsuite unit`, `-m 'not slow and not integration'`); `php-nette` dostal len `_init` poznámku ako Symfony, `python` je bez zmeny. Symfony: `phpunit` = `--exclude-group integration` (stop/quick/full) a nový krok `integration` (`--group integration`, full) podľa vzoru Nette, aby full púšťal všetky testy; riadok o Stop v `php-symfony/rules/tests.md` prepísaný, SPEC §7 má vetu o rýchlych krokoch v stop.
- A5: `CHANGELOG.md` má sekciu `## 0.3.1 — nevydané` už teraz (pravidlo 9 pri zmene šablóny); A8 doplní dátum a ostatné body.
- A6: kód blokuje rovnaké zlyhanie 2× (`blok 1/2`, `blok 2/2`, overuje `t_stop_cap3`) a pri treťom len upozorní (`systemMessage … (3×)`); „3×“ v SPEC, CHANGELOG a hláške je strop zlyhaní, nie počet blokov. Znenie „najviac 3×“ z bodu by bolo nepravdivé a zmena na 3 bloky by menila kontrakt fázy 1, preto všade jedno znenie „najviac 2×, pri treťom (strop 3×) len upozorní“; nejednoznačný README riadok 30 („po 3 rovnakých pokusoch“) a SPEC §4.6 bod 5 („consecutive blocks“) spresnené. Kód sa nemení (v `stop-check.sh` len komentár), preto bez nového prípadu selftestu.
- A7: Stop pri `check.sh` mimo kontraktu 0/1/4 — okrem 3 a ≥ 5 aj exit 2 (syntaktická chyba rozbitého `check.sh` pri in-place inštalácii by inak zapísala `pass`). Pripomienka má tvar `- [check] kontrola sa nedala spustiť (exit N) — pozri <DK_DATA>/errors.log`: prefix `[dev-kit]` je v hlavičke pripomienok, cesta k `errors.log` je úplná.
- A7: `container.state` má tretie pole s menom kontajnera (`<epoch> <running|down> <kontajner>`), aby sa po zmene `container` v configu nepoužil stav iného kontajnera; `check.sh` cache nečíta (`DK_NO_CONTAINER_CACHE`), ale čerstvý stav zapíše.
- A7: symlink s príponou kódu — `dk_blobs` podľa `dk_is_code`; v `pre-bash.sh` súbor len v stage (režim `120000`) podľa `commitGate.ext` ∪ kódové prípony, lebo sada kódu gate je `commitGate.ext` a symlink `.neon` v stage by inak blokoval donekonečna. `dk_session_code_files` sa nemení (symlink ostáva cieľom krokov v Stope).
- A7: riadok `– full: rovnaké kroky ako quick` sa vypíše, keď žiadny zapnutý krok nebeží len v jednom z režimov quick/full (plán: „žiadny krok nie je len pre full“; krok len pre quick by riadok urobil nepravdivým); ide pred riadky krokov a nepočíta sa do `skip`.
- A7: rotácia `errors.log` je priamo v `dk_err` (po zápise), nie pri štarte session ako `decisions.jsonl`.
- A7: `dk_data_dir` bez nového prípadu selftestu — rozdiel (žiadne okno medzi `mkdir` a `chmod`) sa navonok nedá pozorovať, práva 700 kryje `t_data_dir_mode`. `awk -v` ostáva len pri dočasných cestách `$DK_TMP` v `pre-bash.sh` a pri id kroku v `check.sh` (plán menuje cesty súborov projektu).
- A9: výstup pytest je syntetický (formát pytest 8, dva riadky `FAILED`, jeden s parametrom `[2-3]`) priamo v `t_check_known_failures_pytest`, nie v `tests/fixtures/real/` — tam sú podľa SPEC §10 len zaznamenané výstupy reálnych nástrojov. Hodnoty AWS kľúča a hlavičky súkromného kľúča sa v selfteste skladajú z dvoch reťazcov, aby ich vo verejnom repe nehlásil skener tajomstiev. `t_stop_removed_test_file` kryje `rm` aj `git rm` a nový test súbor zmazaný v tej istej session (bez pripomienky). Nové prípady chybu v skriptoch neodhalili, kód sa nemení (SPEC bez zmeny).
- A9: nález mimo rozsahu, neopravený (mení SPEC §3, rozhodne používateľ): `knownFailures` berie z pytest len riadky `FAILED <id>`, nie `ERROR <id>` (chyba fixture/setupu) — známe `FAILED` spolu s neznámym `ERROR` dá krok `známe` a verdikt PASS; PHPUnit chyby (`N) Trieda::metóda`) sa počítajú.
