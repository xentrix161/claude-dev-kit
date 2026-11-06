# dev kit 0.4.2 — diery v ochrane a robustnosť

- Vetva: `main` · Dátum: 2026-11-06 · Stav: schválený
- Zdroj: analýza 4 agentov Opus 5.5 z 2026-11-06 (architektúra skriptov, onboarding, možnosti Claude Code, testy a kvalita); feedback kolegu z 2026-11-05; rozhodnutie používateľa „rozsah nechávam na teba“ → 0.4.2 = len opravy a poistky, zvyšok 0.5.0.

## Ako s týmto plánom pracovať

- Jedno vydanie 0.4.2. Schéma `devkit.json` dostáva jediné nové voliteľné pole `timeoutSec` na kroku (D2).
- Každý bod vlastný commit, správa po slovensky `typ: výstih (D<n>)`. Nič nepushovať a netagovať; vydanie robí používateľ (README, Vydanie).
- Zmena skriptu → v tom istom commite prípad v `tests/selftest.sh` a `docs/SPEC.md`. Zmena šablóny → `CHANGELOG.md` (sekcia `## 0.4.2 — nevydané` vznikne s prvým bodom).
- Kit beží in-place: po každom bode `bash tests/selftest.sh`, na konci `make check`; D1, D3, D5 overiť naživo po `/reload-plugins`.
- Implementácia agentmi Opus 5.5 (nie v hlavnej session), attribution `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Úloha

- Commit gate a kontrola tajomstiev chytia aj commit cez `--continue`; Stop a zámok testu vidia zmeny urobené cez Bash; krok kontroly má časový limit; `forbidFiles` stráži aj Edit/Write; deny text nikdy nestratí príkaz na nápravu; submodul nerozbije guardy; karta upozorní na staré šablóny; šablóny pýtajú súhlas na deštruktívne príkazy; CI stráži guardy nad celým stromom.
- Všade: `make check` PASS, `bash tests/selftest.sh` PASS, `make details` ≤ 3000 tokenov.

## Body

### D1 Commit cez `--continue` (bug)
- `lib.sh:37`: nový `DK_RE_COMMIT_CONT="$DK_RE_GITPFX[[:space:]]+(rebase|merge|cherry-pick|revert|am)([[:space:]]+[^;&|]*)?--continue"`; `pre-bash.sh:406` rýchly filter `*commit*` rozšíriť na `*--continue*`, `pre-bash.sh:412` grep na oba vzory.
- Repo = báza (ako N/U/R dnes), súbory = staged (`git diff --cached --name-only`), bez `-a` a bez správy. Tajomstvá aj gate bežia rovnako ako pri `commit`; deny text hovorí `… pred <príkaz> --continue`.
- SPEC §4.4: veta o `--continue`; Known limitations: `git commit` z editora/`GIT_EDITOR` skriptu sa nedá chytiť. Selftest: `t_bash_continue_gate` (rebase --continue so staged tajomstvom → deny; čisté → allow).

### D2 Časový limit kroku kontroly (robustnosť)
- `devkit.json` krok: `"timeoutSec": N` (voliteľné, predvolene 300; `0` = bez limitu). `lib.sh:440 dk_exec` watchdog `( sleep N; kill ) &` v bash 3.2; v kontajneri obaliť cez `timeout N sh -c …`, ak `timeout` v kontajneri chýba, watchdog zabije klienta `docker exec` (proces v kontajneri môže dobehnúť — do SPEC).
- Výsledok kroku `!` (PARTIAL) s riadkom `! krok <id> prekročil <N> s`; `stop.json` sa zapíše, Stop sa neopakuje každý ťah. Stop hook timeout 600 s ostáva.
- SPEC §3 (pole), §4.5 (PARTIAL dôvody). Selftest: krok `sleep 5` s `timeoutSec: 1` → PARTIAL do 3 s.

### D3 Stop a zámok testu vidia zmeny cez Bash (funkčná medzera)
- `session-card.sh` pri `startup|resume|clear`: `touch "$DK_PDATA/sessions/<id>.t0"`, ak neexistuje. `check.sh:91` v stop móde: `ALL` = session súbory ∪ `dk_changed_files` novšie ako `.t0` (`find -newer`), len kódové prípony.
- `test-lock.sh:48 lock`: do `test-lock.json` uložiť blob každého testu (`git hash-object`). `check.sh` v stop aj auto móde: zamknutý test s iným blobom → riadok `! test <cesta> zmenený počas /dev:fix (zámok)` = FAIL; gate ho vypíše v deny texte. `/dev:fix --unlock` ostáva jediná cesta von.
- SPEC §4.1 (`.t0`), §4.6, §4.8 (`test-lock.json` polia). Selftest: `sed -i` na súbor mimo on-edit → Stop ho skontroluje; zamknutý test zmenený cez Bash → Stop FAIL, commit deny.

### D4 `forbidFiles` v pre-edit (rozchod SPEC a kódu)
- `pre-edit.sh:35`: načítať `secrets.forbidFiles`; Edit/Write do zhody (glob cez `dk_first_glob`, bez ohľadu na veľkosť písmen ako testLock) → `deny` „[dev-kit] <súbor> je v secrets.forbidFiles — tajomstvá sa needitujú cez Claude“. Čítanie pre-edit nestráži (SPEC §4 opraviť: „Edit/Write“).
- Selftest: `t_edit_forbid_files` (`.env` deny, `.env.example` allow).

### D5 Deny text gate: nestratiť príkaz na nápravu (bug)
- `pre-bash.sh:477`: každý blok repa orezať na 12 riadkov (zoznam súborov skrátiť na `… a ďalších N`), posledný riadok `Spusti kontrolu: …` (`pre-bash.sh:822`) pridať až po oreze, nikdy ho nerezať.
- Navrhovaný príkaz: pri ≤ 8 súboroch commitu doplniť `--files <zoznam>`, aby cudzí rozpracovaný súbor nezhodil kontrolu.
- SPEC §4.4 (limit a poradie). Selftest: PARTIAL + 10 súborov + fullWhen → posledný riadok je `Spusti kontrolu`.

### D6 Submodul: súbor sa berie celý ako pridaný (bug)
- `lib.sh:516 dk__added_spec`: keď `git diff HEAD -- <rel>` zlyhá, zistiť koreň cez `git -C "$(dirname <rel>)" rev-parse --show-toplevel`; ak je iný ako `DK_PROJECT`, diff a `ls-files` spustiť v ňom s cestou relatívnou k nemu.
- Selftest: repo so submodulom, úprava súboru v ňom → pridané riadky sú len zmenené, nie `*`.

### D7 `DK_MIN_CC` 2.1.314 (ochrana)
- `lib.sh:41` `DK_MIN_CC=2.1.314` (do tejto verzie hooky s matcherom `Bash` nebežali pri nástroji Monitor → commit mimo gate). README: minimálna verzia. SPEC §0 predpoklady. Selftest `t_card_min_cc` upraviť, ak verziu porovnáva.

### D8 Karta upozorní na staré šablóny (trenie)
- `session-card.sh`: raz za session porovnať `@ <VER>` z hlavičiek `.claude/rules/*.md`, `REVIEW.md`, `.worktreeinclude` s `plugin.json`; staršia → riadok karty `šablóny z kitu <stará> (aktuálna <nová>): /dev:project-init --sync`. Bez hlavičiek nič.
- SPEC §4.7 (riadok karty). Selftest: projekt s `rules/x.md @ 0.3.0` → riadok; bez hlavičky → nič.

### D9 Šablóny `settings.json`: deštruktívne príkazy (medzera šablóny)
- Všetky stacky, `permissions.ask`: `Bash(git reset --hard*)`, `Bash(git clean *)`, `Bash(git stash drop*)`, `Bash(git stash clear*)`, `Bash(git branch -D *)`, `Bash(docker volume rm *)`, `Bash(docker volume prune*)`, `Bash(docker system prune*)`. PHP navyše `Bash(composer require *)`, `Bash(composer update*)`, `Bash(composer remove *)`; Python `Bash(*alembic upgrade *)`, `Bash(*manage.py migrate*)`. `git restore` zámerne nie (`--staged` používa `/dev:commit`).
- `php-*/CLAUDE.md.tmpl`: pravidlo „nová závislosť len so súhlasom, lock commitni spolu“ (ako Python pravidlo 7). SPEC §7 zoznam; CHANGELOG. Selftest `t_templates_php_guards` rozšíriť o `jq index` na nové položky.

### D10 CI: guardy nad celým stromom (CI)
- `.github/workflows/check.yml` nový krok `guards` pred selftestom: `bash -n` na každý `*.sh`, `grep -E` so vzormi `bash4` a `gnu-only` z `.claude/devkit.json` (jq) nad `plugins/dev/scripts/*.sh tests/*.sh tools/*.sh` → nález = FAIL; `shellcheck -S warning`, len ak je `shellcheck` dostupný (`command -v`, inak `skip` s hláškou). Strom je dnes čistý (0 nálezov). Bez zmeny skriptov → bez selftestu; README sekcia CI.

### D11 `--files` výslovne → `runFiles` aj v quick/full (feedback kolegu, bod 5)
- `check.sh:286–295`: ak bol zadaný `--files` a krok má `runFiles`, použiť ho (filtrované `ext`); bez `--files` ostáva `run` prednostne. SPEC §4.5 preformulovať. Selftest: krok s oboma príkazmi, `--quick --files a.php` → beží `runFiles`.

### D12 Šablóna php-nette: krok `migration` (feedback kolegu, bod 1)
- `templates/php-nette/devkit.json`: `{"id":"migration","requires":"vendor/bin/phpunit","run":"php vendor/bin/phpunit --testsuite migration","modes":["full"]}` za `integration`; `CLAUDE.md.tmpl` veta: migračné testy do vlastnej sady, bežia len vo `--full`. `project-init` krok 3: ponúknuť len ak `phpunit.xml` sadu `migration` má. SPEC §7, CHANGELOG, `t_templates_lint` prejde.

### D13 Selftest: súbežnosť podľa CPU (výkon)
- `tests/selftest.sh:3087`: strop 8 zrušiť (max = počet CPU, min 4), dlhé prípady (tabuľky `cmd-parse`) zaradiť prvé. SPEC §9 (predvolené JOBS). Overenie: čas na 12 CPU pod 20 s, zapísať do Odchýlok.

## Dôkaz
- `bash tests/selftest.sh` → `PASS N/N` (N ≥ 167 + nové prípady), `make check` → `[dev-kit] make check: PASS`, `make details` ≤ 3000.
- Naživo po `/reload-plugins`: `GIT_EDITOR=true git rebase --continue` so staged `.env` → deny (D1); `sed -i` na `.sh` a Stop ho skontroluje (D3); deny text s 10 súbormi končí riadkom `Spusti kontrolu` (D5).

## Mimo rozsahu (kandidáti 0.5.0)
- `onFailure: "block"` na hooku Bash (rozhodnutie proti pravidlu 6), marketplace ref `stable` / `git-subdir` s tagom, FileChanged na `devkit.json`, projektový skill `verify`, `!`cmd`` injekcia a `disallowed-tools` v skilloch, `context: fork` pre review, `skills:`/`effort` u agentov, `statusMessage` pre Stop, metadáta `plugin.json`.
- Šablóny: Symfony dorovnať s Nette, `.neon` lint a `local.neon`, viac kontajnerov per krok, `extraKnownMarketplaces`/`plansDirectory`/`attribution` v `settings.json`, referencia `devkit.json` + JSON Schema, README pre kolegu.
- Nové príkazy `/dev:mr`, `/dev:deps`; `/dev:commit` podľa `{{commitStyle}}`.
- Proces: `make release` s poistkami a `make tag` po zelenom CI, eval pre únik z gate a `project-init`, selftest na rotáciu logov a `stats --project`, minimá git ≥ 2.31 a jq v README, upstream ECC pin pri python-testing, výkon pre-bash pri tisíckach súborov.

## Odchýlky
- D5: skrátený zoznam končí riadkom `… ďalšie súbory: N` (ako doterajšie zoznamy kitu: `… ďalšie nálezy: N` v on-edit a pre-bash), nie `… a ďalších N`. Skracujú sa všetky zoznamy bloku (nálezy tajomstiev, súbory, riadky `!` z PARTIAL), najprv najdlhší; samotný orez na konci len keď to nestačí. Pri viacerých repách s deny má blok menej ako 12 riadkov, aby celý text ostal ≤ 20 (SPEC §0). `--files` dostáva kódové súbory commitu (tie, ktoré gate overuje); `dk_deny` text nijako neskracuje (žiadny `dk_cap`), jediný orez bol `head -n 20`, ten je preč.
- D8: riadok šablón ide aj do `systemMessage` (ako údržba kitu či zmena `devkit.json`) — `/dev:project-init` spúšťa používateľ, Claude ho z karty len pripomenie. Porovnanie verzií `dk_ver_lt` je v `session-card.sh` (zdieľa ho kontrola `DK_MIN_CC`), nie v `lib.sh`. Značka `sessions/<id>.tplnote` sa zapíše pri každom porovnaní, nielen pri riadku.
- D3: dva commity — (a) `.t0` a Bash zmeny v Stop, (b) bloby zámku testu. Porovnanie blobov beží v `check.sh` v každom režime (aj quick a full, nielen stop a auto), lebo `pass.json` z quick či full odomyká commit; riadok zámku je pred riadkami krokov a ráta sa do `<n> fail`. Deny text commit gate (`pre-bash.sh`) riadok zámku sám nevypisuje: gate pri zmenenom teste nemá PASS a jeho príkaz `Spusti kontrolu: … check.sh` riadok ukáže. `ctx` Stop replay zahŕňa `test-lock.json`, inak by Stop po `unlock` blokoval z uloženého dôvodu.
- D13: na 12 CPU (8 výkonných + 4 úsporné jadrá) je zisk malý — medián 3 behov `bash tests/selftest.sh` pred 20,85 s (JOBS 8), po 19,62 s (JOBS 12); JOBS 16 dáva ~19,3 s. Postupný beh trvá ~102 s (súčet prípadov ~93 s), súbežnosť dá ~5× bez ohľadu na JOBS nad 8 — strop je réžia spúšťania procesov (bash, git, jq), nie plánovanie; koniec behu na dlhé prípady už nečaká (posledný štart → koniec ~1 s). Navyše oproti plánu: každý prípad maže svoje adresáre sám (súbežne), záverečné `rm -rf` trvalo ~2,2 s. Interné `# čas` je v celých sekundách, varovanie „limit 20 s“ sa preto ešte občas ukáže.
- D2: kontajner sa na `timeout` nepýta samostatným `docker exec` (`command -v`), príkaz ide v jednom obale `sh -c 'timeout 1 true 2>/dev/null && exec timeout "$0" sh -c "$1"; exec sh -c "$1"' <N> <príkaz>` — bez ďalšieho volania na krok a starý busybox (`timeout -t`) spadne na beh bez limitu; prekročenie v kontajneri = exit 124 po aspoň N s, watchdog hostiteľa čaká N + 5 s. Watchdog ukončí celý strom procesov (`ps -A -o pid= -o ppid=`, bez `ps` len samotný job), nie len `$pid`: inak by `sh -c` a jeho potomkovia bežali ďalej. Navyše: neplatná hodnota `timeoutSec` krok zablokuje (`! <id>: neplatný timeoutSec "<x>" (celé číslo ≥ 0)`, ako neznámy `runtime`), lint v on-edit limit nemá, skill `check` vysvetľuje riadok `krok … prekročil`. Súčet limitov krokov Stop môže prekročiť 600 s hooku (šablóna php-nette: `phpstan`, `unit`, `tester` = 900 s) — len poznámka v SPEC §3.
