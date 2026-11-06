# Vývoj kitu

Pre správcu kitu: pracovná kópia, kontroly, CI kitu, údržba, eval suite a vydanie. Používanie kitu v projekte popisuje `README.md`, kontrakt `docs/SPEC.md`, pravidlá pre Claude v tomto repe `CLAUDE.md`.

## Pracovná kópia

```bash
git clone https://github.com/xentrix161/claude-dev-kit.git
claude plugin marketplace add ./claude-dev-kit    # in-place: zmena platí po /reload-plugins
make check                                        # validate --strict, guardy, selftest, rozpočet tokenov
```

- Kontrakt (názvy, cesty, výstupy, `devkit.json`): `docs/SPEC.md`. Ďalšie ciele vypíše `make help`.
- Jednorazový test bez inštalácie: `claude --plugin-dir ./claude-dev-kit/plugins/dev`.
- Skripty sú pre bash 3.2 (macOS) bez GNU-only prepínačov. Text pre ľudí je po slovensky s plnou diakritikou.
- Kit nainštalovaný in-place z pracovnej kópie: rozbitý skript v `plugins/dev/scripts/` hneď zasiahne hooky vo všetkých session a projektoch.

## Rozpočet kontextu

`make details` stráži, aby trvalý kontext kitu ostal pod 3 000 tokenov. Odhad `claude plugin details` závisí od prihlásenia aj od modelu, rozpočet preto overuj v prihlásenom Claude Code. Popisy skillov a agentov drž krátke — príkazové skilly s `disable-model-invocation: true` sa do rozpočtu nerátajú.

## CI kitu

[CI](https://github.com/xentrix161/claude-dev-kit/actions/workflows/check.yml) (`.github/workflows/check.yml`) spustí pri pushi do `main` a pri každom PR na `ubuntu-latest` (bash 5, GNU nástroje) aj `macos-latest` (`/bin/bash` 3.2, BSD nástroje) s najnovším Claude Code z npm povinne `make validate`, `make guards` a `make selftest`, tie prihlásenie nepotrebujú. `make guards` skontroluje celý strom skriptov (`bash -n`, guardy `bash4` a `gnu-only` z `.claude/devkit.json`, `shellcheck -S warning`, ak ho runner má), nielen pridané riadky ako hooky. `make details` tam beží len informatívne (`continue-on-error`): runner nie je prihlásený a `claude plugin details` bez prihlásenia počíta iný, nižší odhad tokenov (pri tomto kite zhruba polovicu), takže rozpočet 3 000 tokenov stráži len lokálny `make check` v prihlásenom Claude Code.

## Údržba

- **Hlučné pravidlo:** oprav vzor alebo prah v šablóne kitu, pridaj prípad do `tests/selftest.sh` a v projektoch spusti `/dev:project-init --sync`.
- **Claude Code:** po `claude update` spusti `make check`. Ak novú funkciu Claude Code zvládne sám, príslušný kus kitu zruš.
- **ECC:** raz mesačne `make upstream` (karta to pripomenie po 30 dňoch, len keď plugin beží z pracovnej kópie kitu) vypíše zmenené prevzaté kusy. Zmeny preber ručne a posuň pin v `plugins/dev/PROVENANCE.md`. Klon ECC hľadá v `ECC_DIR`, predvolene `<KIT>/../ECC` (vedľa pracovnej kópie kitu).

## Eval suite

Pred vydaním a po zmene skillov `check`, `commit`, `review`, `fix`, `mr` alebo `deps` spusti `make eval`. Prípady v `plugins/dev/evals/` bežia nad syntetickým projektom v dočasnom adresári, každý 3× s kitom a 3× bez neho, Bash v sandboxe. Každý beh agenta aj sudca `llm` graderov stojí tokeny, preto eval nie je v `make check`.

Prípady (gradery podrobne v SPEC §9):

| prípad | čo overuje |
|---|---|
| `check-partial` | `/dev:check` pri nebežiacom kontajneri hlási PARTIAL, nie PASS, a kontajner nespúšťa |
| `commit-no-attribution` | `/dev:commit`: číslo úlohy z vetvy, jeden riadok, bez AI atribúcie a pushu |
| `commit-style-jira` | `/dev:commit` podľa pravidla o commitoch v `CLAUDE.md` (kľúč Jiry z vetvy) |
| `commit-partial-gate` | prosba o commit pri PARTIAL: commit gate commit nepustí, Claude nemení `devkit.json`, neobchádza hooky a ponúkne možnosti |
| `review-format` | `/dev:review`: riadkový formát nálezov, vloženie príkazu a vynechaný riadok |
| `fix-locked-test` | `/dev:fix`: padajúci test, zámok, oprava kódu bez zmeny testu |
| `mr-describe` | `/dev:mr`: päť sekcií, migrácia a premenná prostredia z diffu, verdikt z `pass.json`, review agentmi; bez `gh`, `glab` a pushu |
| `deps-one-package` | `/dev:deps` s atrapou composeru: update jedného balíka, changelog z `vendor/`, `--full` pred commitom `composer.lock`; bez hromadného update |

- Tabuľka: `WITH` je skóre s kitom (cieľ 1.00), `W/OUT` ten istý prompt bez kitu, `Δ` rozdiel. Príkazy `/dev:*` bez kitu neexistujú, takže bez neho prejdú len gradery typu „niečo sa nestalo“ (žiadny push, žiadne PASS). O výsledku preto rozhoduje `WITH`; `Δ` blízko nuly znamená, že prípad netestuje kit a treba ho sprísniť.
- Prípad pod prahom (`--threshold`, predvolene 1.0) skončí `make` chybou. Padnuté gradery s vysvetlením ukáže `plugins/dev/evals/results/<čas>/report.html`, rovnaké dáta pre skripty sú v `aggregate-result.json`.
- Agenti aj sudca bežia na Sonnete (`EVAL_MODEL`, `EVAL_JUDGE`): predvolený model účtu býva drahší a sudca `haiku` dáva falošné FAIL pri správnej odpovedi. Lacný prvý odhad: `EVAL_ARGS="--runs 1"` (16 behov, zhruba 1,5 USD; najdrahší je `mr-describe` s dvomi agentmi). Ďalšie voľby cez `EVAL_ARGS`, napr. ladenie jedného prípadu `EVAL_ARGS="--case check-partial --runs 1 --ablation none"` alebo súbežnosť `-j 4`. Report ostáva lokálne, keď eval spúšťa Claude Code; z terminálu sa zverejní ako súkromný artifact na claude.ai (`--no-publish` ho nechá lokálne).
- `EVAL_ARGS="--max-cost-usd 0"` len načíta a skontroluje súbory suite, nespustí ani jeden beh (0 USD).
- Nový prípad: adresár `<prípad>/` s `prompt.md`, `case.yaml`, `scaffold.sh` a `graders/*.md` podľa SPEC §9; tvar súborov a varianty fixtúry stráži selftest `t_evals_suite`.

## Vydanie

```bash
make release VERSION=0.5.0             # poistky, verzia v plugin.json, dátum v CHANGELOG, validate --strict, tag --dry-run
git add plugins/dev/.claude-plugin/plugin.json CHANGELOG.md
git commit -m "vydanie dev 0.5.0"
git push
make tag                               # po zelenom CI: tag dev--v0.5.0 na origin
```

- `make release` zmení verziu, až keď je strom čistý, vetva je `main`, verzia je vyššia ako posledný tag `dev--v*`, `CHANGELOG.md` má sekciu `## 0.5.0 — nevydané` a prejde `make check`; inak skončí s hláškou bez zmeny súboru. Potom nahradí `— nevydané` dnešným dátumom. Keď `claude plugin validate --strict` alebo `tag --dry-run` zlyhá, `plugin.json` aj `CHANGELOG.md` vráti.
- `make tag` taguje len čistý strom, ktorého `HEAD` je po `git fetch` zhodný s `origin/main` a CI pre ten commit skončilo `success` (`gh run list`). Bežiace alebo zlyhané CI tag odmietne. Bez `gh` taguj ručne: `claude plugin tag --push plugins/dev`. GitHub Release kit nevytvára, vydanie je len tag.

Verzia je len v `plugins/dev/.claude-plugin/plugin.json`. Bez jej zvýšenia ostatní novú verziu nedostanú; inštalácia z lokálnej cesty verziu ignoruje.
