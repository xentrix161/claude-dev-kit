# dev kit 0.5.0 — šablóny, proces vydania, nové príkazy

- Vetva: `main` · Dátum: 2026-11-06 · Stav: schválený
- Zdroj: sekcia „Mimo rozsahu“ plánu `dev-kit-0.4.2.md` (analýza 4 agentov z 2026-11-06); dotazník 2026-11-06: rozsah = šablóny + proces + lacné novinky Claude Code; hook Bash bez `onFailure: block` (timeout 60 s + výkon); nové príkazy `/dev:mr` aj `/dev:deps`; pripínanie verzie v marketplace sa nerieši (kit zatiaľ nikto nemá nainštalovaný).

## Ako s týmto plánom pracovať

- Jedno vydanie 0.5.0 (minor: nové príkazy, nová schéma `$schema` v `devkit.json`, zmena hook timeoutu).
- Každý bod vlastný commit `typ: výstih (E<n>)`; nič nepushovať a netagovať; vydanie cez `make release` + `make tag` (E7 ide prvý, aby vydanie 0.5.0 už šlo novým postupom).
- Zmena skriptu → selftest + SPEC v tom istom commite; zmena šablóny → CHANGELOG (`## 0.5.0 — nevydané`); nový skill → eval prípad v `plugins/dev/evals/` (beh `make eval` len na pokyn používateľa).
- Implementácia agentmi Opus 5.5 v dávkach: (1) E7, E8, E13; (2) E1, E2, E3; (3) E4, E5, E6; (4) E9; (5) E10, E11, E12. Always-on kontext ≤ 3000 tokenov (`make details`) — popisy nových skillov krátke.

## Úloha

- Kolega nainštaluje kit a nastaví Nette aj Symfony projekt bez autora: README pre používateľa, referencia `devkit.json` so schémou, Symfony šablóna rovnocenná s Nette. Vydanie má poistky a tag vzniká až po zelenom CI. Commit gate neunikne timeoutom pri bežne veľkom commite. Po commite nadväzuje `/dev:mr`, závislosti aktualizuje `/dev:deps`.

## Body

### E7 `make release` s poistkami, `make tag` po zelenom CI (proces)
- `Makefile:release`: pred zmenou verzie `make check`, čistý strom (`git status --porcelain` prázdny), vetva `main`, verzia > posledný tag (`sort -t. -k1,1n -k2,2n -k3,3n`, bez `sort -V`), sekcia `## <verzia> ` v CHANGELOG povinná (exit 2, nie pripomienka); pri chybe validate vrátiť `plugin.json`.
- Nový cieľ `make tag`: HEAD pushnutý (`git fetch && git rev-parse origin/main`), `gh run list --commit HEAD --json conclusion` = `success` (bez `gh` → hláška a exit 2), až potom `claude plugin tag --push plugins/dev`; voliteľne `RELEASE=1` → `gh release create` z CHANGELOG sekcie.
- README sekcia Vydanie (nový postup, 4 kroky), CLAUDE.md tabuľka. Selftest: Makefile sa netestuje; dôkaz = `make release VERSION=0.0.0` na špinavom strome → exit 2 s hláškou (zapísať do Odchýlok).

### E8 Hook Bash: timeout 60 s a výkon pri tisíckach súborov (robustnosť)
- `hooks.json`: PreToolUse Bash `timeout: 60`; SPEC §4 Known limitations: timeout hooku pustí príkaz ďalej (rozhodnutie: bez `onFailure: block`, pravidlo 6).
- `pre-bash.sh:636–641,763–770` a `check.sh:152–167,286–293`: filter prípon a quoting v jednom `awk` namiesto `$(dk_ext)`/`$(dk_shq)` per súbor; O(n²) `case` dedup nahradiť `sort -u`/`comm`; `{files}` posielať po dávkach (≤ 64 KiB na dávku, Linux `MAX_ARG_STRLEN`), výsledky krokov zlúčiť.
- Selftest: 3 000 staged súborov → `pre-bash.sh` pod 5 s (meranie v Odchýlkach, nie v kóde); dávkovanie: krok `runFiles` s 5 000 súbormi dá jeden výsledok. Pozor na limit 20 s selftestu.

### E13 SPEC a údržba dát (dlh)
- SPEC §2/§4.9: rotácia `decisions.jsonl` nad 10 MB do `.1` (len pri `startup`), `stats.sh` číta `.1`; čistenie `projects/<phash>` zmazaných worktree (karta pri `startup`: adresár bez `pass.json` novšieho ako 90 dní a bez existujúcej cesty → zmazať; cesta sa uloží do `project.json` pri prvom zápise). Selftest: rotácia a čistenie.
- `PROVENANCE.md` vs SPEC §9: pin `python-testing` zjednotiť (overiť `tools/upstream.sh --no-fetch`).

### E1 Symfony šablóna rovnocenná s Nette (medzera šablóny)
- `templates/php-symfony/CLAUDE.md.tmpl`: `{{commitStyle}}`, pravidlo o `git push`, `{{handoffDoc}}`, sekcia Overovanie práce, `{{appUrl}}`/`{{startCommand}}` — podľa `php-nette/CLAUDE.md.tmpl`.
- `rules/api-platform.md` len keď `composer.json` má `api-platform/*` (podmienka v `project-init` krok 4 a v `_init`); Webpack Encore: `public/build/` do `deny` a `rules/twig-frontend.md` s vetvou AssetMapper/Encore podľa `composer.json`.
- SPEC §7, CHANGELOG, selftest `t_templates_lint` + kontrola, že oba PHP `CLAUDE.md.tmpl` majú rovnaké `{{…}}` premenné.

### E2 Nette: `.neon` lint a lokálny config (medzera šablóny)
- `project-init`: cestu lokálneho configu zistiť (`app/config/config.local.neon` | `app/config/local.neon` | `config/local.neon`) a dosadiť do `forbidFiles`, `.worktreeinclude`, pravidla 10 a `rules/nette.md` cez `{{localConfig}}`.
- `lint[".neon"]`: `php vendor/bin/neon-lint {file}` s `requires` (nette/neon ≥ 3.3 má `neon-lint` — overiť `?`). SPEC §7, CHANGELOG, selftest šablón.

### E3 `settings.json` šablón: tímový režim a plány (novinky CC)
- Tímový režim: `extraKnownMarketplaces` (dev-kit, GitHub URL repa) + `enabledPlugins: {"dev@dev-kit": true}` — kolega po dôvere priečinka dostane ponuku inštalácie; `plansDirectory: "docs/plans"`; `attribution: false` ako otázka v `project-init` (predvolene nie).
- `project-init` krok (otázky), SPEC §7, CHANGELOG, selftest `jq` na nové kľúče.

### E4 Referencia `devkit.json` + JSON Schema (trenie)
- `docs/devkit-json.md` po slovensky: každý kľúč, príklad, kedy použiť (kroky `run`/`runFiles`/`modes`/`timeoutSec`, guardy, páry, secrets, testLock, commitGate, disabledRules). SPEC ostáva kontrakt, referencia je pre ľudí; README odkazuje.
- `plugins/dev/devkit.schema.json` (draft-07, `additionalProperties: false`), šablóny `devkit.json` dostanú `"$schema": "../../…"`? — cesta k schéme v nainštalovanom plugine nie je stabilná → `$schema` ako URL na raw GitHub súbor z tagu (overiť `?`). Selftest: každá šablóna aj `.claude/devkit.json` kitu validuje proti schéme (`jq` nestačí → kontrola kľúčov cez `jq` zoznam povolených kľúčov; plná validácia len ak je `check-jsonschema` dostupný, inak skip).

### E5 README pre kolegu (text)
- README: inštalácia, prvé spustenie, `/dev:project-init`, čo robia hooky (gate stráži len Claudove commity, nie terminál), kedy `/dev:review` vs vstavané `/code-review` a `/security-review`, tímový režim (gate sa zapne všetkým s pluginom; `docs/handoff.md` vylúčiť z repa — `project-init` ho dá do `.git/info/exclude`), Chrome MCP pre `/dev:debug` a `/dev:test` jednou vetou s odkazom.
- Správcovská časť (CI kitu, eval, vydanie, vývoj) do `docs/DEVELOPMENT.md`; CLAUDE.md pravidlo 13 doplniť o nový súbor. Žargón (PARTIAL, `knownFailures`) vysvetliť pri prvom výskyte.

### E6 `/dev:commit` podľa `{{commitStyle}}` (trenie)
- `skills/commit/SKILL.md`: formát správy z pravidla 11 `CLAUDE.md` projektu (Jira kľúč `ABC-123`, conventional commits so scope, jazyk); bez pravidla ostáva `[#XX] typ: výstih` po slovensky. Číslo úlohy z vetvy: aj `ABC-123`. Eval prípad `commit-style-jira`.

### E9 Lacné novinky Claude Code (S, jeden commit alebo dva)
- `hooks.json`: `statusMessage` pre Stop (`[dev-kit] Stop kontrola…`); `plugin.json`: `homepage`, `repository`, `license`, `keywords`.
- Skilly: `disallowed-tools: Edit, Write, NotebookEdit` pre `explain`, `stats`, `debug`; `` !`bash "${CLAUDE_PLUGIN_ROOT}/scripts/stats.sh" --project "$PWD" || true` `` v `/dev:stats` a `git status --short`/`git diff --cached --stat` v `/dev:commit`.
- Agenti: `tools` bez `Grep`/`Glob`, ak sú naozaj nedostupné (overiť v docs tools-reference `?`); `skills: [ecc-mysql-patterns]` pre performance-optimizer, `[ecc-accessibility]` pre a11y-architect. `make validate` + `make details` ≤ 3000.

### E10 `/dev:mr` (nový príkaz)
- `skills/mr/SKILL.md`: popis PR/MR z `git diff <base>...HEAD` (base = `main`|`master`|`develop`, zisti z `origin/HEAD`), plánu v `docs/plans/`, posledného verdiktu `/dev:check` (`pass.json`), migrácií a krokov po nasadení; sekcie Čo, Prečo, Ako overiť, Riziká. Pred popisom review vetvy agentmi `dev:ecc-pr-test-analyzer` a `dev:ecc-silent-failure-hunter` (nálezy do popisu alebo opraviť pred MR — otázka používateľovi). `gh pr create`/`glab mr create` až po výslovnom súhlase; bez CLI vypíše text na skopírovanie. `disable-model-invocation: true`, popis skillu ≤ 120 znakov.
- README, SPEC §8 (skilly), eval `mr-describe` (syntetický projekt: popis obsahuje migráciu a verdikt, žiadny `gh` bez súhlasu).

### E11 `/dev:deps` (nový príkaz)
- `skills/deps/SKILL.md`: `composer outdated --direct` | `pip list --outdated`; po jednom balíku: prečítať UPGRADE/CHANGELOG balíka (WebFetch len so súhlasom), aktualizovať, `/dev:check --full`, commit `composer.json` + `composer.lock` (`requirements*.txt`/`poetry.lock`) spolu cez `/dev:commit`; `composer audit` nález → návrh opravy verzie. Nikdy `composer update` bez balíka. `settings.json` šablón už pýta súhlas na `composer require|update` (0.4.2).
- README, SPEC §8, eval `deps-one-package` (aktualizuje jeden balík, commit obsahuje lock, žiadne hromadné `update`).

### E12 Eval (proces)
- Nové prípady z E6, E10, E11 + `commit-partial-gate` (Claude po PARTIAL nemení `devkit.json`, commit nevznikne, ponúkne možnosti). `make eval` beží na pokyn používateľa pred vydaním; výsledok do Odchýlok.

## Dôkaz
- `make check` → PASS, `bash tests/selftest.sh` → `PASS N/N` (N ≥ 179 + nové), `make details` ≤ 3000, `make validate` 2×.
- `make release VERSION=0.5.0` odmietne špinavý strom; `make tag` odmietne bez zeleného CI (E7).
- Naživo po `/reload-plugins`: commit s 3 000 súbormi prejde gate pod 60 s (E8); `/dev:mr` v pilotnom Nette projekte vypíše popis bez volania `gh` (E10); `/dev:deps` aktualizuje jeden balík (E11).
- `make eval` pred vydaním na pokyn (E12).

## Mimo rozsahu (kandidáti 0.6.0)
- `onFailure: "block"` (zamietnuté 2026-11-06), FileChanged na `devkit.json`, projektový skill `verify`, `context: fork` pre review, viac kontajnerov per krok, pripínanie verzie v marketplace (`stable`/`git-subdir`), selftest diery (rotácia, `stats --project`, `test-lock` okraje), minimá git ≥ 2.31 a jq v README + CI job so starším gitom, eval pre `project-init` a `learn`.

## Odchýlky
- E7 dôkaz: `make release VERSION=0.0.0` na špinavom strome (necommitnutý `Makefile` a plán) → `[dev-kit] strom nie je čistý (git status) — vydanie ide len z commitnutého stavu`, exit 2, strom bez zmeny; `make tag` rovnako. Ostatné vetvy `release` a `tag` (vetva, tag existuje, nižšia verzia, chýba CHANGELOG, zlyhaný validate či `tag --dry-run` → súbory vrátené, HEAD nepushnutý, CI bez behu / beží / zlyhalo / success, bez `gh`) overené na syntetickom repe v scratchpade (`git init` + bare origin, atrapy `claude` a `gh`), nie na klone kitu.
- E7: verzia a sekcia v CHANGELOG sa kontrolujú pred `make check` (lacné poistky prvé); všetky stále pred zmenou `plugin.json`.
- E7: bez `RELEASE=1 … gh release create` — pokyn používateľa: žiadne GitHub Releases, vydanie je len tag.
