# CLAUDE.md — dev-kit

## Projekt

- Plugin `dev` pre Claude Code (hooky, príkazy `/dev:*`, agenti, šablóny projektov) a marketplace `dev-kit`, ktorý ho distribuuje.
- Kontrakt (názvy, cesty, výstupy, hlášky, `devkit.json`): `docs/SPEC.md`. Pri rozpore so zvyškom repa platí SPEC.
- Stav úloh a rozhodnutia: `docs/handoff.md`.
- Repo je verejné na GitHube; kolegovia dostávajú len vydané verzie.

## Stack

- Bash skripty (macOS `/bin/bash` 3.2 aj bash 5, BSD aj GNU nástroje), `jq`, `git`.
- Skilly a agenti: Markdown s YAML frontmatter; manifesty: JSON.
- Kit tu používa sám seba: `.claude/devkit.json` so stackom `shell`.

## Príkazy

Spúšťaj z koreňa repa.

| Úloha | Príkaz | Zdravý výstup |
|---|---|---|
| kontrola zmien | `/dev:check` | `[dev-kit] check quick: PASS · N ok · 0 fail · 0 skip · S s` |
| všetko pred commitom | `make check` | `[dev-kit] make check: PASS` |
| selftest | `bash tests/selftest.sh` | `PASS N/N` |
| jeden prípad | `bash tests/selftest.sh <podreťazec názvu>` | `PASS N/N` |
| manifesty a frontmatter | `make validate` | `✔ Validation passed` (2×) |
| rozpočet kontextu | `make details` | `[dev-kit] always-on ~N tok. ≤ 3000 …` |
| vydanie | `make release VERSION=x.y.z` | postup v `README.md`, sekcia Vydanie |

- `FAIL N/M`, `not ok - …` alebo chyba validate = nie je hotovo.
- `SKIP` ani `PARTIAL` v `/dev:check` nie je PASS — povedz to výslovne.

## Overovanie práce

- Pred „hotovo" spusti `/dev:check`, pred commitom `make check`. Do odpovede vlož súhrnný riadok výstupu.
- Padá prípad selftestu → oprav skript, nie test. Test meníš len keď je preukázateľne zlý — povedz prečo.
- Zmena hooku → over ju aj v reálnej session (`/reload-plugins`), nielen selftestom.
- Po 2 neúspešných pokusoch o tú istú opravu zastav, zhrň zistenia a navrhni iný prístup.

## Architektúra

```
.claude-plugin/marketplace.json   marketplace dev-kit (bez verzie)
plugins/dev/.claude-plugin/       plugin.json — jediné miesto verzie
plugins/dev/hooks/hooks.json      SessionStart, PreToolUse, PostToolUse, Stop
plugins/dev/scripts/              lib.sh (spoločné funkcie) + skript na každý hook, check.sh
plugins/dev/skills/               príkazy /dev:* a referenčné skilly
plugins/dev/agents/               read-only agenti
plugins/dev/templates/            šablóny projektov (<stack>/, common/, skills/ = vrstva B)
plugins/dev/PROVENANCE.md         kusy prevzaté z ECC s pinom
tests/selftest.sh                 kontrakty skriptov, každý prípad vo vlastnom git repe
tools/                            details.sh (rozpočet), upstream.sh (ECC)
docs/SPEC.md                      kontrakt
```

- Nový prípad selftestu: funkcia `t_<meno>()` + riadok `t "<popis>" t_<meno>` v zozname na konci súboru.

## Pravidlá

1. Skripty: `#!/usr/bin/env bash`, bash 3.2, bez GNU-only prepínačov (`sed -i ''`, `grep -E`, nie `-P`); stráži to `guard:bash4` a `guard:gnu-only`.
2. Text pre ľudí (hlášky, skilly, README, šablóny) po slovensky s plnou diakritikou; identifikátory, príkazy a cesty ostávajú.
3. Zmena správania skriptu alebo hooku → uprav `docs/SPEC.md` v tom istom commite.
4. Oprava alebo nové správanie skriptu → prípad v `tests/selftest.sh`.
5. Always-on kontext pluginu ≤ 3000 tokenov (`make details`); popisy skillov drž krátke.
6. Hooky bez `.claude/devkit.json` musia ostať no-op; nebežiaci kontajner ani chýbajúci nástroj nikdy neblokujú.
7. Kusy z ECC: zmenu zapíš do `plugins/dev/PROVENANCE.md`; `plugins/dev/LICENSES/` nemeň.
8. Šablóny sú generické: žiadne mená projektov, ľudí, klientov ani dáta. Platí pre celé repo — je verejné.
9. Zmena šablóny → záznam v `CHANGELOG.md`; projekty ju dostanú cez `/dev:project-init --sync`.
10. Verzia len v `plugins/dev/.claude-plugin/plugin.json`; bez jej zvýšenia kolegovia zmenu nedostanú.
11. Komentáre krátke alebo žiadne: len čo z kódu nevidno; bez histórie a meraní.
12. Commit: slovensky, `typ: výstih` (`feat`, `fix`, `docs`, …); `git push` len na výslovný pokyn.
13. Zmena zastará tento súbor, `README.md` alebo `REVIEW.md` → uprav ich v tom istom commite.

## Pasce

- Kit je nainštalovaný in-place z tejto pracovnej kópie: rozbitý skript v `plugins/dev/scripts/` hneď zasiahne hooky vo všetkých session a projektoch.
- BSD grep číta `[^\s]` ako „nie spätná lomka, nie s" — v zátvorkách používaj `[:space:]`, `[:alnum:]_` (SPEC §3).
- `claude plugin details` počíta aj skilly s `disable-model-invocation: true`, hoci ich popis v kontexte nie je — rozpočet stráži `tools/details.sh`.
- Selftest musí bežať aj z hooku: premenné `CLAUDE_*` a `DEVKIT_DATA` si nastavuje sám a na `$HOME/.claude` nesmie siahnuť.
- `make` musí fungovať v GNU 3.81 aj BSD make — bez GNU funkcií.

## Compact instructions

- Zachovaj zoznam zmenených súborov, stav každého (hotové / rozpracované) a posledný výsledok `/dev:check`.
- Zachovaj číslo úlohy, otvorené rozhodnutia, čo používateľ zamietol, a ďalší krok.
- Zachovaj presné príkazy na overenie.
