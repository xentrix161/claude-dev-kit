# Changelog

- Formát: `## <verzia> — <dátum>`, najnovšie hore; verzia = `version` v `plugins/dev/.claude-plugin/plugin.json`.
- Posun pinu ECC (P3) zapíš ako odrážku: kusy + nový commit.

## 0.2.0 — 2026-10-28

- `check.sh`: krok, ktorý sa nedal spustiť (exit 125–127, chyba prostredia, nebežiaci kontajner, krok bez príkazu), má riadok `! <krok>: dôvod` a verdikt je `PARTIAL` s exit 4 namiesto PASS. `pass.json` sa nezapíše, takže commit gate taký stav nepustí. Riadok `–` ostáva pre kroky, ktoré sa zmien netýkajú; phpcs `No files were checked` patrí medzi ne.
- `check.sh`: kroky so známymi zlyhaniami sa v súhrne rátajú zvlášť (`· N známe`), nie medzi `ok`.
- Stop: stav kontroly je per session (`sessions/<id>.stop.json`), takže súbežná session nevynuluje počítadlo blokov; pri `PARTIAL` dostane model pripomienku, ktoré kroky neprebehli.
- Hlášky o tajomstvách ukazujú len `súbor:riadok — ****`, bez znakov hodnoty.
- SPEC opisuje, čo commit gate dokazuje (obsah súborov skontrolovaný v pracovnom strome, nie výsledný strom commitu).

## 0.1.1 — 2026-10-28

Opravy z prvých `/dev:project-init` (prvé tri projekty):

- Šablóna `php-nette`: krok `latte` volá `latte-lint` pre každý súbor zvlášť — `latte-lint` číta len prvú cestu, takže pri viacerých súboroch ostatné neskontroloval. Test v `tests/selftest.sh`.
- Šablóna `php-nette`: `ask` stráži `docker stop/restart/rm` nad všetkými kontajnermi (predtým len DB kontajner), rovnako ako `php-symfony` a `python`.
- `/dev:project-init`: make ciele, ktoré zastavia či prestavia kontajnery alebo menia DB či index, navrhne do `ask` (`Bash(make <cieľ>*)`), len ak ich `Makefile` má.
- `/dev:project-init`: `handoffDoc` je `docs/handoff.md`; sledovaný TODO alebo plán nie, lebo `/dev:handoff` doň pripisuje datované sekcie. V lokálnom režime ide nesledovaný `handoffDoc` do `.git/info/exclude`.
- Lokálny režim nedáva z kitu nič do gitu: `/dev:project-init` pridá `docs/plans/` do `.git/info/exclude` aj do `.worktreeinclude` a `/dev:plan` plán necommituje. V tímovom režime ide plán s prvou zmenou ako doteraz.

## 0.1.0 — 2026-10-27

- Prvá verzia: marketplace `dev-kit` + plugin `dev` (in-place z lokálnej cesty).
- Hooky: úvodná karta (SessionStart), zámok testu a commitnutá migrácia (PreToolUse Edit/Write), tajomstvá + commit gate (PreToolUse Bash), lint + guardy v pridaných riadkoch (PostToolUse), Stop kontrola nad súbormi session.
- `scripts/check.sh` — jediný zdroj pravdy pre `/dev:check`, Stop a commit gate.
- Príkazy: `check`, `commit`, `review`, `test`, `debug`, `fix`, `plan`, `learn`, `handoff`, `explain`, `stats`, `project-init`.
- Referenčné skilly `ecc-*` + `task-tldr`, 4 read-only agenty `ecc-*`, šablóny `php-nette`, `php-symfony`, `python` a vrstva B.
- Prevzaté z ECC @ b92f181 (MIT) — zoznam v `plugins/dev/PROVENANCE.md`.
- Údržba: `make check`, `make upstream`, `make release`, `tests/selftest.sh`.

### Opravy z overenia (pred vydaním 0.1.0)

- Strop always-on rozpočtu zvýšený z 1 500 na 3 000 tokenov (`tools/details.sh`, `make details`).
- Commit gate: dôvod zamietnutia končí presným príkazom `bash "<scripts>/check.sh" --auto|--full --project "<P>"`, aby Claude vedel kontrolu spustiť sám (príkazové skilly majú `disable-model-invocation`).
- `on-edit.sh`: hlavička skloňuje aj zámeno („1 nález … — oprav ho“, „2 nálezy … — oprav ich“).
- `review` a `commit`: znenie zladené so štýlom „stručne, ale úplne“ (review vypíše celý zoznam nálezov v predpísanom formáte, commit message ostáva jednoriadková).
- Upstream ECC (P3, `make upstream` 28. 10.): `ecc-python-testing` ← `skills/python-testing` @ 25278e7d (lifespan pri `ASGITransport`).
- Tajomstvá: `secrets.patterns` z `devkit.json` rozširujú predvolené vzory kitu (zjednotenie), jeden nález na `súbor:riadok`; vo vzoroch nie je `\s` ani `\w` v hranatých zátvorkách (`[:space:]`, `[:alnum:]_`) a do grep idú vždy cez `-e`; `on-edit.sh` kontroluje tajomstvá aj v pridaných riadkoch (hodnota maskovaná).
- Commit gate (`pre-bash.sh`): rozpozná globálne prepínače gitu pred `commit` (`-C` aj s cestou s medzerami v úvodzovkách, `-c`, `-p`/`-P`, `--no-pager`, `--git-dir`, `--work-tree`), premenné prostredia a obaly (`env`, `command`, `time`, …); regexy sú len v `lib.sh` (`DK_RE_GITPFX`, `DK_RE_COMMIT`, `DK_RE_ADD`). Všetky `cd` pred commitom sa skladajú, nerozlúštiteľný `cd` = cwd session; viacriadkový príkaz sa vyhodnotí ako celok. `git add -p/-i/-e`, `git add -A -f` a názvy, ktoré git vypíše len v C úvodzovkách, odmietne s radou; `git add -f` započíta ignorované súbory. Známe obmedzenie ostáva `sh -c '…git commit…'`.
- `check.sh`: `--files` zužuje súbory v každom režime a `pass.json` zapíše presne ich bloby (`/dev:commit` kontroluje len svoju skupinu); prepínače v ľubovoľnom poradí; `changedLinesOnly: "stop"` (šablóny pri phpstan a mypy); filter zmenených riadkov rozumie absolútnym cestám z kontajnera, formátu latte-lint, Symfony lint a twig a chyby parsovania aj pády nástroja ponechá vždy; ANSI sekvencie sa odstránia; exit 126/127 a chyby dockeru sú SKIP; `knownFailures` berie identifikátory len z riadkov PHPUnit `N) Trieda::metóda` a pytest `FAILED`.
- Stop: párové pravidlá a nová pripomienka zmazaných test metód (`testRemoved`) sa vyhodnotia raz za session ešte pred skratkou „nezmenený stav“; samotné pripomienky idú ako `additionalContext` bez chybovej hlášky, zlyhanie ostáva `decision: block`, po 3× rovnakom stave `systemMessage`.
- Úvodná karta: jeden JSON objekt (karta = kontext pre Clauda, `systemMessage` = varovania pre používateľa), statický JSON bez `jq`, riadok `chýba docker`, denná kontrola minimálnej verzie Claude Code (`DK_MIN_CC`), pri stacku python upozornenie na worktree bez `.venv/`.
- Worktree: cwd v prepojenom worktree toho istého repa má prednosť pred `--project` aj `CLAUDE_PROJECT_DIR`; skilly už nepotrebujú obchádzky.
- Hlášky hookov nesú id pravidla (`[lint:.php, guard:…]`, `[guard:<id>]`, `[pair:<id>]`, `[testRemoved]`), aby sa falošný poplach dal nahlásiť a vypnúť cez `disabledRules`.
- `stats.sh`: predvolene aktuálny projekt (`--all` výslovne), riadok `obdobie: N dní` a podiel `PASS na prvý raz`.
- Dátový adresár kitu sa vytvára s právami 700.
- Zámok testu a otázka pri commitnutej migrácii platia aj pre inú podobu cesty (`./`, `..`, `//`, iná veľkosť písmen na APFS).
- Agenty `ecc-silent-failure-hunter` a `ecc-pr-test-analyzer` sú bez `memory: local` (ostávajú len na čítanie a nevytvárajú `.claude/agent-memory-local/`); poznatok môžu navrhnúť voliteľným riadkom „Na zapamätanie:“, ktorý `/dev:learn` po schválení zapíše do `.claude/rules/` projektu (pravidlá agenti načítajú pri každom behu).
- `project-init`: hlavička podľa typu súboru (markdown `<!-- dev-kit: … -->`, `.worktreeinclude` `# dev-kit: …`, JSON bez hlavičky); `.claude/worktrees/` zapíše do `.git/info/exclude` (lokálne) alebo navrhne do `.gitignore` (tím).
- Šablóny: deny pravidlá ukotvené ku koreňu projektu (`Edit(/vendor/**)`), rovnaké zástupné mená a nadpis `## Compact instructions` vo všetkých stackoch, guard `test-skip`.
- Výstupy skillov podľa pravidla „stručne, ale úplne“ (záver prvý, celé vety, úplné zoznamy) namiesto TLDR.
- Dokumentácia: `docs/SPEC.md` zosúladená s rozhodnutiami D1–D20; README radí presunúť pôvodný `~/.claude/skills/task-tldr` a po 2 týždňoch zmazať staré `~/.claude/commands/*`; `PROVENANCE.md` má stĺpec `date adopted` (2026-10-27).
