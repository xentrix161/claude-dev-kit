# Provenience prevzatého obsahu

- Zdroj: ECC (`https://github.com/affaan-m/ECC`), lokálny klon `~/Projects/_tools/ECC`, pin `b92f181` (2026-10-11).
- Licencia ECC: MIT, © 2026 Affaan Mustafa — plný text v `LICENSES/ECC-MIT.txt`; pri distribúcii kitu musí ostať pri kite.
- Každý prevzatý kus je upravený (slovenčina, stručne, ale úplne, `docker exec` namiesto npm, bez „80 % coverage“ a conventional commits) → upstream sa preberá ručne, nie kopírovaním.
- `make upstream` (`tools/upstream.sh`) číta tabuľku nižšie podľa poradia stĺpcov: 2. stĺpec cesta v ECC, 3. stĺpec pin; 4. stĺpec je dátum prevzatia do kitu.
- Jeden riadok = jeden zdroj; kus z viacerých zdrojov má viac riadkov.
- Po prevzatí zmien prepíš pin v riadku na nový commit a zapíš to do `CHANGELOG.md`.

## Kusy odvodené z ECC

| kit path | ECC source path | ECC commit | date adopted | changes |
|---|---|---|---|---|
| `skills/ecc-mysql-patterns/` | `skills/mysql-patterns` | b92f181 | 2026-10-27 | SK, skrátené; MySQL 5.7/8, Dibi + Doctrine parametre, EXPLAIN, indexy, N+1; `paths:` |
| `skills/ecc-e2e-testing/` | `skills/e2e-testing` | b92f181 | 2026-10-27 | SK, skrátené; Playwright POM, flaky testy; bez Vercel/npm častí |
| `skills/ecc-change-impact/` | `skills/change-impact` | b92f181 | 2026-10-27 | SK, skrátené; pred rizikovou zmenou jadra (validátory, triggery, verejné API) |
| `skills/ecc-accessibility/` | `skills/accessibility` | b92f181 | 2026-10-27 | SK, skrátené; WCAG 2.2 pre serverové šablóny (Latte, Twig), bez Reactu; `paths:` |
| `skills/ecc-production-audit/` | `skills/production-audit` | b92f181 | 2026-10-27 | SK, skrátené; `disable-model-invocation: true` |
| `skills/ecc-python-patterns/` | `skills/python-patterns` | b92f181 | 2026-10-27 | SK, skrátené; `paths: **/*.py` |
| `skills/ecc-python-testing/` | `skills/python-testing` | 25278e7d | 2026-10-28 | SK, skrátené; pytest; bez povinného pokrytia |
| `agents/ecc-silent-failure-hunter.md` | `agents/silent-failure-hunter.md` | b92f181 | 2026-10-27 | SK, read-only, `model: inherit`, `maxTurns: 30`, bez pamäte, voliteľný riadok „Na zapamätanie:“ pre /dev:learn, výstup max 15 nálezov |
| `agents/ecc-pr-test-analyzer.md` | `agents/pr-test-analyzer.md` | b92f181 | 2026-10-27 | SK, read-only, `model: sonnet`, `maxTurns: 30`, bez pamäte, voliteľný riadok „Na zapamätanie:“ pre /dev:learn |
| `agents/ecc-a11y-architect.md` | `agents/a11y-architect.md` | b92f181 | 2026-10-27 | SK, read-only, `model: sonnet`, `maxTurns: 30`; serverové šablóny |
| `agents/ecc-performance-optimizer.md` | `agents/performance-optimizer.md` | b92f181 | 2026-10-27 | SK, read-only, `model: inherit`, `maxTurns: 30`; PHP/MySQL namiesto Node |
| `templates/skills/ecc-design-system/` | `skills/design-system` | b92f181 | 2026-10-27 | vrstva B (kopíruje sa do projektu na požiadanie); SK, skrátené |
| `templates/skills/ecc-api-design/` | `skills/api-design` | b92f181 | 2026-10-27 | vrstva B; SK, skrátené |
| `templates/skills/ecc-inherit-legacy-style/` | `skills/inherit-legacy-style` | b92f181 | 2026-10-27 | vrstva B; SK, skrátené |
| `templates/skills/ecc-seo/` | `skills/seo` | b92f181 | 2026-10-27 | vrstva B; SK, skrátené |
| `skills/check/` | `skills/verification-loop` | b92f181 | 2026-10-27 | vlastný skill; z ECC len postup overovania; výsledok výhradne z `scripts/check.sh` |
| `skills/fix/` | `commands/orch-fix-defect.md` | b92f181 | 2026-10-27 | vlastný skill; repro test → zámok testu (`test-lock.sh`) → oprava → `check.sh --auto` |
| `skills/learn/` | `commands/learn.md` | b92f181 | 2026-10-27 | vlastný skill; návrhy do pamäte, `.claude/rules/` alebo `guards`/`pairs`, zápis len po schválení |
| `skills/learn/` | `commands/learn-eval.md` | b92f181 | 2026-10-27 | vyhodnotenie návrhov pred zápisom |
| `skills/project-init/` | `skills/codebase-onboarding` | b92f181 | 2026-10-27 | vlastný skill; detekcia stacku, infer-conventions, šablóny s hlavičkou `dev-kit:` |
| `skills/project-init/` | `commands/project-init.md` | b92f181 | 2026-10-27 | dry-run disciplína, nič bez súhlasu |
| `skills/review/` | `agents/code-reviewer.md` | b92f181 | 2026-10-27 | vlastný skill (základ `~/.claude/commands/review.md`); z ECC checklist a prah istoty |
| `skills/review/` | `skills/security-review` | b92f181 | 2026-10-27 | prechod `--security` (základ `~/.claude/commands/security.md`) |
| `skills/test/` | `skills/tdd-workflow` | b92f181 | 2026-10-27 | vlastný skill (základ `~/.claude/commands/test.md`); RED → GREEN → REFACTOR s dôkazom |

## Mimo ECC (len pre prehľad, `make upstream` ich nečíta)

- `skills/task-tldr/` — kópia používateľovho `~/.claude/skills/task-tldr/SKILL.md` bez úprav.
- `skills/commit/`, `skills/explain/` — z používateľových `~/.claude/commands/commit.md`, `explain.md`.
- `skills/debug/`, `skills/plan/`, `skills/handoff/`, `skills/stats/`, hooky, `scripts/`, šablóny `php-*`/`python` — vlastné.
