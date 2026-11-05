# dev kit 0.4.1 — otvorené nálezy z fáz 1 a 2

- Vetva: `main` · Dátum: 2026-11-05 · Stav: schválený
- Zdroj: nálezy „mimo rozsahu, neopravené“ z `docs/plans/dev-kit-0.3.1-0.4.0.md` (A3/A9, B8, B10, B13) a handoff z 2026-11-04; rozhodnutia používateľa z 2026-11-05 (dotazník, všetky štyri odporúčané možnosti).

## Ako s týmto plánom pracovať

- Jedno vydanie 0.4.1 (opravy bez zmeny schémy `devkit.json`; mení sa text deny hlášky, SPEC §3 a šablóna `php-nette`).
- Každý bod vlastný commit, správa po slovensky `typ: výstih (C<n>)`. Nič nepushovať a netagovať; vydanie robí používateľ podľa README (sekcia Vydanie), ako pri 0.4.0.
- Zmena skriptu → v tom istom commite prípad v `tests/selftest.sh` a `docs/SPEC.md` (pravidlá 3 a 4). Zmena šablóny → `CHANGELOG.md` (pravidlo 9). Sekcia `## 0.4.1 — nevydané` v CHANGELOG vznikne s prvým bodom, dátum doplní používateľ pri vydaní.
- Kit beží in-place: po každom bode `bash tests/selftest.sh`, na konci `make check`; zmenu `pre-bash.sh` (C1) a `check.sh` (C2, C5) overiť aj naživo po `/reload-plugins`.
- Rozhodnutia používateľa (2026-11-05, nemeniť bez opýtania): R6 deny text commit gate nikdy nekáže Claudovi meniť config, len navrhnúť vypnutie používateľovi; R7 pytest `ERROR <id>` je zlyhanie ako `FAILED <id>`; R8 Phinx príkazy meniace DB dostanú `ask` ako Doctrine; R9 body C1–C5 idú do 0.4.1 hneď, bez čakania na spätnú väzbu.

## Úloha

- Po 0.4.1 deny text commit gate pri PARTIAL a `commit/SKILL.md` hovoria to isté (config mení len človek); pytest fixture chyba nedá PASS; Phinx `migrate`/`rollback`/`seed:run`/`breakpoint` v projektoch zo šablóny pýtajú potvrdenie; selftest beží aj s nastaveným `CLAUDE_CONFIG_DIR`; zápisy JSON z `check.sh`, `test-lock.sh` a `stats.sh` nerozbijú viacbajtový znak.
- Všade: `make check` PASS, `bash tests/selftest.sh` PASS, `make details` ≤ 3000 tokenov, selftest pod 20 s.

## Body

### C1 Deny text commit gate: únik ako návrh používateľovi (R6)
- `plugins/dev/scripts/pre-bash.sh:355,357`: oba texty `Únik:` preformulovať tak, aby adresát (Claude) config nemenil:
  - `ok` ≥ 1: `Únik: navrhni používateľovi <príčina> a kontrolu zopakuj, alebo mu navrhni dočasné vypnutie: disabledRules <ids> v .claude/devkit.json (config nemeň sám, počkaj na jeho rozhodnutie).`
  - `ok` = 0: `Únik: vypnutie krokov by dalo SKIP, nie PASS — navrhni používateľovi <príčina> a kontrolu zopakuj, alebo mu navrhni dočasné vypnutie gate: disabledRules commitGate v .claude/devkit.json (kontrola tajomstiev aj Stop bežia ďalej; config nemeň sám).`
  - slovo `krok|kroky` pred `disabledRules` ostáva v hláške pri `ok` ≥ 1 (`dočasné vypnutie kroku|krokov:`), aby výber id ostal čitateľný.
- `docs/SPEC.md:403–408` (§4.4, PARTIAL explanation): nové znenia doslovne; veta, že text nikdy nekáže Claudovi meniť config (zhoda s `commit/SKILL.md:97`).
- `README.md:38`: „alebo navrhnúť používateľovi dočasné vypnutie cez `disabledRules` …“ namiesto „dočasne vypnúť“. `REVIEW.md`: ak cituje text úniku, zladiť (overiť grepom `disabledRules`).
- Selftest: asserty v `t_bash_commit_partial_explained` (`tests/selftest.sh:638`), `t_bash_commit_partial_one_ok` (`:658`) a `t_bash_commit_partial_all_ids` (`:681`) na nové znenia; navyše `want_not 'dočasne vypni'` (staré znenie nesmie ostať nikde v deny texte).

### C2 knownFailures: pytest `ERROR <id>` (R7)
- `plugins/dev/scripts/check.sh:225 dk_known_ok`: k vzoru `^FAILED ([^[:space:]]+)` pridať `^ERROR ([^[:space:]]+\.py(::[^[:space:]]+)?)( |$)` — id je cesta (chyba zberu modulu) alebo `cesta::test` (chyba fixture/setupu). Obmedzenie na `.py` zámerne: `ERROR` na začiatku riadku píšu aj iné nástroje (PHPUnit `ERRORS!` nie, ale napr. vlastné skripty), tie nie sú identifikátory.
- `DK_EXCERPT_RE` (`check.sh:14`) už má `^ERROR`; bez zmeny.
- `docs/SPEC.md:212–213` (§3 `knownFailures`): „pytest `^FAILED <id>` and `^ERROR <id>` (short summary; `<id>` is `<path>::<test>` or, for a collection error, the path)“.
- Selftest: `t_check_known_failures_pytest` (`tests/selftest.sh:2047`) rozšíriť o výstup s `FAILED tests/test_x.py::test_y` (známy) + `ERROR tests/test_x.py::test_w - fixture 'db' not found` (neznámy) → krok FAIL, verdikt FAIL; s druhým vzorom `test_w` → krok `známe`, PASS; `ERROR tests/test_conf.py` (chyba zberu, bez `::`) → id `tests/test_conf.py`. Jedna kontrola, že riadok `ERROR: something else` bez `.py` id nedá.

### C3 Šablóna php-nette: `ask` na Phinx (R8)
- `plugins/dev/templates/php-nette/settings.json` `permissions.ask`: pridať `"Bash(*phinx migrate*)"`, `"Bash(*phinx rollback*)"`, `"Bash(*phinx seed:run*)"`, `"Bash(*phinx breakpoint*)"` hneď za Doctrine pravidlá. `phinx status`, `create`, `seed:create` ostávajú voľné. V Doctrine projektoch sú pravidlá nečinné (ako Doctrine pravidlá v Dibi projektoch).
- `plugins/dev/templates/php-nette/rules/db-dibi.md`: odrážka ako v `db-doctrine.md:31`: „`phinx migrate`, `rollback` a `seed:run` len na výslovný pokyn (menia DB).“ `CLAUDE.md.tmpl:96` (pravidlo 5, `db:dibi`): doplniť „; `phinx migrate` len na pokyn“.
- `docs/SPEC.md:915` (zoznam `php-nette/settings.json`): doplniť Phinx príkazy do výpočtu. `php-symfony` šablóna bez zmeny (Phinx tam nie je).
- `CHANGELOG.md` sekcia 0.4.1: zmena šablóny, projekty ju dostanú cez `/dev:project-init --sync`.
- Selftest: `t_templates_lint` (`tests/selftest.sh:1852`) už overuje JSON; pridať do `t_templates_php_guards` (`:2201`) alebo nový `t_templates_phinx_ask`: `jq -e '.permissions.ask | index("Bash(*phinx migrate*)")'` pre všetky štyri položky a že `php-symfony/settings.json` ich nemá.

### C4 Selftest harness: `CLAUDE_CONFIG_DIR`
- `tests/selftest.sh:35`: do `unset` pridať `CLAUDE_CONFIG_DIR` (pamäť agentov v `pre-edit.sh:18` sa skladá z neho; harness má vlastný `HOME`).
- Overenie bez nového prípadu (zmena harnessu, nie skriptu): `CLAUDE_CONFIG_DIR=/nonexistent bash tests/selftest.sh agent_memory` → PASS; zapísať do Odchýlok ako dôkaz. `CLAUDE.md` Pasce: rozšíriť vetu o premenných, ktoré si selftest nastavuje sám (`CLAUDE_*` vrátane `CLAUDE_CONFIG_DIR`).

### C5 `jq -R` z rúry: viacbajtové znaky na hranici bloku
- Príčina (B13): jq 1.7.1 pri `-R` zo stdin rozdelí viacbajtový znak na hranici čítacieho bloku na U+FFFD. `pre-compact.sh` to už rieši cez `--arg`.
- `plugins/dev/scripts/check.sh:386` (`partial.json`): riadky `! …` (≤ 5) odovzdať cez `--arg l "$(… | head -n 5)"` a `lines: ($l | split("\n") | map(select(length > 0)))`; `check.sh:402` (`pass.json`): `--rawfile b "$DK_TMP/blobs.snap"` a `blobs: ($b | split("\n") | map(select(length > 0) | split("\t") | {(.[0]): .[1]}) | add // {})`.
- `plugins/dev/scripts/test-lock.sh:48`: `--arg f "$rels"` a `files: ($f | split("\n") | map(select(length > 0)))`.
- `plugins/dev/scripts/stats.sh:32`: logy zlepiť do `$DK_TMP/stats.jsonl` (`dk_tmpdir`) a čítať `--rawfile r …`, `($r | split("\n") | map(try fromjson catch null) | map(select(type == "object")))` namiesto `inputs`.
- `docs/SPEC.md`: v §4 (hook discipline / lib.sh) jedna veta: skripty nečítajú text do jq cez `-R` z rúry, len `--arg`/`--rawfile` (dôvod: jq 1.7.1, U+FFFD na hranici bloku); `grep -n 'jq -R' plugins/dev/scripts/` prázdny okrem komentára.
- Selftest `t_jq_multibyte` (vzor `t_hook_text_cap`): (a) `check.sh --auto` s krokom, ktorého názov a hláška nebežiaceho kontajnera obsahujú diakritiku a riadok `! …` dlhý 20 000 znakov `č` → `partial.json` bez U+FFFD (`grep -c $'\xef\xbf\xbd'` = 0) a `.lines[0]` dĺžka sedí; (b) `test-lock.sh lock` s 3 000 cestami `tests/žlťočka_<n>.php` → `lock.json` bez U+FFFD, `.files | length` = 3000; (c) `stats.sh` nad logom 100 kB s diakritikou v `reason` → výstup bez U+FFFD a správny počet záznamov. Selftest musí ostať pod 20 s.

### C6 PreCompact naživo (používateľ)
- Po vydaní 0.4.1 v reálnej session `/compact`: v súhrne kompakcie musia byť fakty session (zmenené súbory, posledný výsledok kontroly, handoff). Bez zmeny kódu; výsledok zapísať do handoffu.

### C7 Správa kolegovi po vydaní (používateľ)
- Text pripravený v konverzácii 2026-11-05 (verzia 0.4.1, `claude plugin update dev@dev-kit`, čo nové a čo potrebujeme späť: výstup `/dev:project-init --dry-run` z Nette pilota, falošné zamietnutia commit gate, hlášky Stop). Po odpovedi doladiť šablónu `php-nette` v ďalšej verzii.

## Poradie a overenie

1. C4 (harness) → C2 → C5 → C1 → C3; po každom `bash tests/selftest.sh`, po C5 a C1 aj naživo (`/reload-plugins`: commit bez PASS po PARTIAL → nový text úniku; `/dev:check` po zmene `.sh` → `partial.json`/`pass.json` čitateľné jq).
2. Na konci `make check`, `make details`, `claude plugin validate --strict` 2×, `grep -rn` osobných ciest mimo `docs/handoff.md` = 0.
3. `/dev:handoff`, potom vydanie 0.4.1 používateľom (README Vydanie) a C7.

## Mimo rozsahu

- Allowlist príkazov v `devkit.json`, eval v CI, nové stacky (bez zmeny oproti plánu 0.4.0).
- `make eval` pred 0.4.1 netreba: skilly `check`, `commit`, `review`, `fix` sa nemenia (README Údržba); C1 mení len hook.

## Odchýlky

- C4: filter selftestu hľadá podreťazec v popise prípadu, nie v mene funkcie, takže `agent_memory` nevyberie nič (`FAIL 0/0`). Dôkaz preto s filtrom `'agent kitu'` (tri prípady `pre-edit: agent kitu …`): `CLAUDE_CONFIG_DIR=/nonexistent bash tests/selftest.sh 'agent kitu'` pred zmenou `FAIL 1/3` (pamäť → deny s cestou `/nonexistent/agent-memory/`), po zmene `PASS 3/3`; celý selftest s nastaveným `CLAUDE_CONFIG_DIR` `PASS`.
- C5: jq 1.7.1 pri `-R` rozdelí viacbajtový znak len v riadku dlhšom ako blok čítania (~4 kB); kratšie riadky prejdú celé. Test preto má v každej časti riadok cez dve hranice bloku (zásah nezávisí od parity):
  - (b) namiesto 3 000 krátkych ciest (tie chybu nespustia ani so starým skriptom a `test-lock.sh lock` s 3 000 argumentmi beží ~3 s, selftest by prekročil 20 s) 300 ciest `tests/žlťočka_<n>.php` a jedna s 4 200 × `ž`;
  - (c) `dk_log` nemá pole `reason` → diakritika je v `rule`, ktoré `stats.sh` vypisuje (poškodenie inde by vo výstupe nebolo vidno); 12 záznamov s `rule` 4 500 × `ď` (~100 kB), test overí `záznamy: 12` a riadok pravidla `12/0/0/0/0/0`;
  - `pass.json`: riadok `blobs.snap` (`cesta<TAB>blob`) blok čítania neprekročí (cesta ≤ PATH_MAX), chyba tu v praxi nenastáva; `--rawfile` podľa plánu, v časti (a) 5 ciest s diakritikou a presný kľúč ako stráž.
  - SPEC §4: existujúcu vetu o texte hookov (`--arg`, nie `jq -R`) som rozšíril na všetky skripty a `--rawfile`, druhú vetu nepridal.
  - Proti skriptom pred zmenou (jq-1.7.1, macOS): celý pôvodný `plugins/dev/scripts/` → `FAIL 1/1` (`partial.json`); nové skripty len so starým `test-lock.sh` → FAIL (`test-lock.json`), len so starým `stats.sh` → FAIL (riadok pravidla); len so starým zápisom `pass.json` → PASS (viď vyššie).
