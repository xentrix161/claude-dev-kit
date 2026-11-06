---
name: mr
description: "Popis PR/MR vetvy z diffu, plánu, verdiktu /dev:check a migrácií, s review agentmi. gh/glab len so súhlasom, nikdy push."
argument-hint: "[base]"
disable-model-invocation: true
disallowed-tools: Edit, Write, NotebookEdit
allowed-tools:
  - 'Bash(git branch --show-current)'
  - 'Bash(git status *)'
  - 'Bash(git log *)'
  - 'Bash(git diff *)'
  - 'Bash(git rev-parse *)'
  - 'Bash(git merge-base *)'
  - 'Bash(git symbolic-ref --short refs/remotes/origin/HEAD)'
  - 'Bash(git remote get-url origin)'
---

# /dev:mr — popis PR/MR vetvy

Z hotovej vetvy pripraví názov a popis PR/MR, ktorý sa dá rovno vložiť. Nič nepushuje a PR/MR vytvorí len po výslovnom súhlase. Komunikuj po slovensky. Argumenty: `$ARGUMENTS`

## 1. Base a vetva

- Base: prvé slovo argumentu (`develop`, `origin/develop`); inak `git symbolic-ref --short refs/remotes/origin/HEAD` (`origin/main` → `main`); inak prvá existujúca z `main`, `master`, `develop` (`git rev-parse --verify -q refs/heads/<b>` alebo `refs/remotes/origin/<b>`). Nič nenájdené → spýtaj sa na base a skonči.
- Porovnávaj s `origin/<base>`, ak existuje, inak s lokálnou `<base>`. `git fetch` nespúšťaj — údaje sú podľa posledného fetchu, povedz to jednou vetou, keď na tom záleží.
- Vetva: `git branch --show-current`. Vetva = base alebo prázdny `git log <base>..HEAD` → povedz to jednou vetou a skonči.
- Necommitnuté zmeny (`git status --short`) do PR/MR nepatria — vymenuj ich jedným riadkom pred popisom.

## 2. Zdroje (spusti paralelne)

- Commity: `git log --reverse --format='%h %s' <base>..HEAD`; súbory a rozsah: `git diff --stat <base>...HEAD` a `git diff --shortstat <base>...HEAD`.
- Diff: `git diff <base>...HEAD`. Nad ~400 zmenenými riadkami alebo 15 súbormi čítaj len stat a diff vybraných súborov (migrácie, config, nové verejné API, súbory z plánu); lock súbory, generovaný a vendorovaný kód, snapshoty a preklady vynechaj.
- Číslo úlohy z vetvy alebo commitov ako v `/dev:commit` (`fix/85-…` → `#85`, `feature/ABC-123-…` → `ABC-123`, `[#85]` v správach).
- Plán: `docs/plans/<číslo>-*.md` (aj `#<číslo>-*.md`) alebo plán zmenený v diffe. Z neho Úloha (Prečo), Dôkaz (Ako overiť), Riziká.
- Pravidlo o commitoch projektu: riadok `Commit:` v `CLAUDE.md` (inak `CLAUDE.local.md`, `AGENTS.md`) — určuje tvar názvu a jazyk popisu.
- Config `.claude/devkit.json`: `migrations.paths`, `check.fullWhen`, `pairs[].when`, `stack`, `container`, `appRoot`.
- Posledný verdikt `/dev:check` (markery `check.sh`, SPEC §4.5) — jeden príkaz, len číta:

```bash
d="${DEVKIT_DATA:-$HOME/.claude/dev-kit}/projects/$(cd -P "${CLAUDE_PROJECT_DIR}" && git rev-parse --show-toplevel | tr -d '\n' | git hash-object --stdin | cut -c1-12)"; for f in partial pass; do [ -f "$d/$f.json" ] && jq -c --arg f "$f.json" '{file: $f, when: (.time | strflocaltime("%d.%m. %H:%M")), time, mode, head, lines}' "$d/$f.json"; done; ls -t "$d/logs" 2>/dev/null | grep -E '^check-(quick|full)-' | head -n 1
```

Výklad:
- `partial.json` → posledná kontrola `PARTIAL` (`mode`, `when`, dôvody z `lines`) — neúplne overené.
- `pass.json`, ale posledný log `check-<režim>-<epoch>.log` má `epoch` väčší ako `time` → posledná kontrola nedala PASS → `neoverené`.
- `pass.json` s `head` = HEAD (kontrola po poslednom commite) alebo `head` = `HEAD~1` (kontrola pred ním) → `/dev:check --<mode>: PASS (<when>)`. Iný `head` → `PASS pre starší stav (<head krátko>)`.
- Nič z toho → `neoverené`. Pri `neoverené`, PARTIAL, starom stave alebo režime `quick` navrhni `/dev:check --full` pred MR (sám ho nespúšťaj).

## 3. Review vetvy

- Diff len s dokumentáciou (žiadna prípona z `commitGate.ext` ani kódu) → review preskoč, v Rizikách `review netreba (len dokumentácia)`.
- Inak spusti v JEDNEJ správe paralelne read-only agentov `dev:ecc-pr-test-analyzer` a `dev:ecc-silent-failure-hunter`. Daj im presný rozsah: `git diff <base>...HEAD`, zoznam zmenených súborov, stack, `container` a `appRoot` z `devkit.json`, cestu k plánu.
- Agent nie je dostupný → prejdi diff sám podľa prechodov 1 a 2 z `${CLAUDE_PLUGIN_ROOT}/skills/review/SKILL.md` a povedz to jednou vetou.
- Nálezy agentov sú kandidáti: každý over v kóde (okolie riadku, volajúci, testy), nepotvrdený zahoď, podobné zlúč. 🔴 a 🟡 idú do Rizík, 🔵 vymenuj pod popisom (najviac 5).

## 4. Popis

Názov: v tvare pravidla o commitoch projektu (číslo úlohy, typ), výstih celej vetvy z nadpisu plánu, inak z prvého commitu vetvy. Príklad `[#42] feat: zľava objednávky s limitom`, Jira `ABC-123 Zľava objednávky s limitom`.

Jazyk: podľa pravidla o commitoch, inak podľa správ commitov, bez oboch po slovensky. Anglický popis má sekcie `What · Why · How to test · Risks · After deploy`.

Sekcie (všetky, v tomto poradí; prázdna sekcia = `—`):
- **Čo** — 2–6 odrážok zo zmien, nie zoznam súborov; pre recenzenta, nie pre stroj.
- **Prečo** — z plánu (Úloha, Zdroj), inak z commitov. Dôvod nikde → `<doplň: prečo>`, nevymýšľaj.
- **Ako overiť** — verdikt `/dev:check` z kroku 2, nové alebo zmenené testy (`súbor` + scenár), Dôkaz z plánu; ručný krok (URL, príkaz) len keď ho plán alebo diff obsahuje.
- **Riziká** — overené nálezy review `🔴|🟡 N. súbor:riadok — výstih`, neúplné overenie, zmena už commitnutej migrácie, súbory z `check.fullWhen` a `pairs[].when`, otvorené riziká z plánu.
- **Po nasadení** — len to, čo dokazuje diff:
  - migrácie: pridané súbory podľa `migrations.paths` (bez configu `migrations/`, `db/migrations/`, `database/migrations/`, `src/Migrations/`, `alembic/versions/`, `*/migrations/*.py`); príkaz z `CLAUDE.md`, `Makefile` alebo `composer.json` scripts, inak len súbor
  - premenné prostredia: nové kľúče v `*.dist`, `*.example`, `.env*` šablónach, `config.local.neon.dist` alebo v pridaných riadkoch (`%env(…)%`, `getenv`, `$_ENV`, `os.environ`) — len mená, nikdy hodnoty
  - cache: diff mení DI/config/routy (`*.neon`, `config/**`) a projekt má príkaz na čistenie cache (`CLAUDE.md`, `Makefile`, deploy skript) → ten príkaz
  - cron: zmenený crontab, scheduler (`#[AsCronTask]`, `#[AsPeriodicTask]`, `scheduler.yaml`) alebo nový konzolový príkaz bez plánovania → otázka „naplánovať?“
  - nič → `—`

## 5. Výstup a vytvorenie

V jednej správe:
1. Riadok `base <base> · <N> commitov · <súbory> súborov (+X −Y)`, prípadne riadok s necommitnutými zmenami.
2. `Názov: <názov>`
3. Popis v bloku ```` ```markdown ```` s nadpismi `## Čo`, `## Prečo`, `## Ako overiť`, `## Riziká`, `## Po nasadení` (na skopírovanie).
4. 🔵 nálezy pod blokom, ak sú.
5. Záver podľa stavu:
   - `git remote get-url origin`: GitHub → `gh`, GitLab → `glab`; nástroj over len cez `command -v gh` / `command -v glab`. Bez remote, iný hosting alebo bez nástroja → jedna veta, že text je na skopírovanie, a koniec.
   - Vetva nie je na origin (`git rev-parse --verify -q refs/remotes/origin/<vetva>` nič) alebo sa líši od HEAD → `vetva nie je na origin` / `origin/<vetva> nezodpovedá HEAD` — push je na používateľovi; text je na skopírovanie, koniec.
   - Inak jedna otázka s možnosťami (AskUserQuestion, ak je dostupný): `vytvoriť PR/MR` · `vytvoriť ako draft` · `najprv opraviť nálezy <čísla>` (len s 🔴/🟡; pri 🔴 ju daj prvú ako odporúčanú) · `nie, len text`. Počkaj na odpoveď.
6. Po súhlase (ďalšia správa) presne jeden príkaz, s `--draft` pri drafte:

```bash
gh pr create --base <base> --head <vetva> --title "<názov>" --body-file - <<'EOF'
<popis>
EOF
glab mr create --source-branch <vetva> --target-branch <base> --title "<názov>" --description "$(cat <<'EOF'
<popis>
EOF
)" --yes
```

   Ukáž URL z výstupu. Chyba (prihlásenie, PR/MR už existuje) → cituj ju a skonči, iné prepínače neskúšaj. `najprv opraviť` → oprav, potom `/dev:check` a `/dev:commit`; `/dev:mr` spusti znova používateľ.

## Pravidlá

- NIKDY `git push` (ani `--push` cez `gh`/`glab`) — push si rieši používateľ.
- `gh` a `glab` až po výslovnom súhlase v odpovedi na otázku; pred ním ani `gh auth status`, `gh pr list` či `glab mr list`.
- Nevymýšľaj: čo nie je v diffe, pláne ani commitoch, do popisu nepíš; neznáme označ `<doplň: …>`.
- Hodnoty tajomstiev a premenných prostredia nikdy nevypisuj.
- Komunikuj po slovensky.
