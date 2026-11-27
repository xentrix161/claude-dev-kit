## Zástupné symboly

Platí pre `{{…}}` v šablónach `<stack>/` (`devkit.json`, `AGENTS.md.tmpl`, rules); `common/plan.md` vypĺňa `/dev:plan`, popisné `{{…}}` v `common/REVIEW.md` rieši krok 4.

- Detekovateľné vyplň a v pláne ukáž s dôkazom `súbor:riadok`.
- Nezistené rieš bez otázky podľa stĺpca Nezistené: „zmaž“ = riadok, ktorý je len o symbole (odrážka, riadok tabuľky či stromu), inak najmenšiu časť riadku, ktorá bez symbolu nedáva zmysel (` · {{database}}`, ` level {{phpstanLevel}}`, ` ({{appUrl}})`, vedľajšiu vetu za `;`); „len číslo“ = zmaž len verziu. Voliteľný krok alebo pair `devkit.json` s nezisteným symbolom vypusti a vymenuj v pláne. Pri neznámom vstupe povinného kroku označ inštaláciu overovania ako zablokovanú.
- Pýtaj sa len na `{{projectDescription}}`, `{{commitStyle}}` (git log bez histórie alebo bez jednotného štýlu), `{{container}}` (compose chýba), `{{localConfig}}` (php-nette, žiadny kandidát) a `{{migrationsDir}}` pri Phinx, keď sa `paths.migrations` nedá prečítať bez spustenia configu — v otázkach kroku 2, limit 4 ostáva. Chýbajúci vstup povinnej kontroly rieš pri zablokovanej inštalácii.
- **Nástroje bez kroku:** nástroj, ktorého krok alebo lint init vypustil (projekt ho nemá), z `AGENTS.md.tmpl` zmaž rovnako, so symbolom aj bez neho — riadok Príkazov, jeho meno v riadku Kvalita, vetu v Overovaní práce (PHPStan a baseline, integračné testy pri `/dev:check --auto` bez kroku `integration`, sada `migration` bez kroku `migration`, PHPCS, latte-lint, neon-lint, ruff, mypy, pytest). `AGENTS.md` nesmie kázať overovanie nástrojom, ktorý projekt nemá.
- Symbol adresára (`…Dir`) končí `/`; v `devkit.json` z neho glob `{{entityDir}}**`.

Stack: N = php-nette, S = php-symfony, P = python.

| Symbol | Stack | Zdroj | Nezistené |
|---|---|---|---|
| `{{projectName}}` | N S P | `name` v `composer.json` (časť za `/`) alebo v `pyproject.toml`, inak meno adresára repa | — |
| `{{projectDescription}}` | N S P | `description` v `composer.json`/`pyproject.toml`, prvý odsek `README.md` alebo `AGENTS.md` | otázka 4 |
| `{{domainTerms}}` | N S P | glosár alebo zoznam pojmov v `CLAUDE.md`, `AGENTS.md`, `README.md` | zmaž |
| `{{architectureNotes}}` `{{projectPitfalls}}` | N S P | vstupné body a vzory, resp. pasce z existujúceho `CLAUDE.md`/`AGENTS.md` | zmaž |
| `{{commitStyle}}` | N S P | `git log --format=%s -50`: tvar riadku s príkladom (`[#123] typ: výstih`, Jira `ABC-123 výstih`, `typ(scope): výstih`) a jazyk — `/dev:commit` podľa neho píše správy | otázka 4 |
| `{{handoffDoc}}` | N S P | krok 1 handoff (`docs/handoff.md`) | — |
| `{{testCredentialsFile}}` | N S | krok 1 testovací login | zmaž |
| `{{container}}` `{{appRoot}}` | N S P | krok 1 kontajner: `container_name`, cieľ mountu koreňa repa | compose chýba → otázka 1; `container: ""` → oba `""`, riadok Docker v Stacku zmaž |
| `{{localConfig}}` | N | prvý existujúci z `app/config/config.local.neon`, `app/config/local.neon`, `config/local.neon`, inak `*local*.neon` z `addConfig()` v `Bootstrap.php` | otázka 4; projekt bez lokálneho configu → zmaž riadky so symbolom aj položku `forbidFiles` |
| `{{dbContainer}}` | N S | DB služba v compose (krok 1); len text v `AGENTS.md`, pole `devkit.json` to nie je | zmaž |
| `{{run}}` | N S P | `docker exec {{container}} ` (keď `working_dir` služby nie je `{{appRoot}}`: `docker exec -w {{appRoot}} {{container}} `); P aj `.venv/bin/` alebo `uv run ` | `""` (hostiteľ) |
| `{{bin}}` | P | `_init` v `devkit.json`: `.venv/bin/`, `/opt/venv/bin/` v kontajneri | `""` (nástroje v PATH) |
| `{{pythonEnv}}` | P | podľa `{{run}}`: venv `.venv` na hostiteľovi, uv, alebo kontajner `{{container}}` | — |
| `{{appUrl}}` | N S P | lokálna URL v `README.md`/`CLAUDE.md`/`AGENTS.md`, inak `ports` webovej služby (`8080:80` → `http://localhost:8080`) | zmaž |
| `{{startCommand}}` `{{startHealthyOutput}}` | N S P | cieľ `Makefile` (`up`, `start`) alebo príkaz z `README.md`; zdravý výstup z toho istého zdroja | zmaž riadok |
| `{{phpVersion}}` | N S | `require.php` alebo `config.platform.php` v `composer.json`, image PHP služby | len číslo |
| `{{netteVersion}}` `{{latteVersion}}` `{{dibiVersion}}` `{{ormVersion}}` `{{symfonyVersion}}` | N (`symfonyVersion` S) | `composer.lock`: `nette/application`, `latte/latte`, `dibi/dibi`, `doctrine/orm`, `symfony/framework-bundle` (major.minor), inak obmedzenie v `require` | len číslo |
| `{{pythonVersion}}` | P | `requires-python` v `pyproject.toml`, `.python-version`, image v compose | len číslo |
| `{{database}}` | N S P | image DB služby v compose (`mysql:8.0` → MySQL 8.0), `server_version` v konfigurácii Doctrine | zmaž |
| `{{framework}}` | P | závislosť `django`, `flask`, `fastapi` … v `pyproject.toml`/`requirements*.txt` | zmaž |
| `{{unitCommand}}` `{{integrationCommand}}` `{{migrationTestCommand}}` | N S | celý projektový príkaz s wrapperom a argumentmi podľa [detekcie PHP](php.md), rovnako pre tabuľku príkazov a krok s `runtime: host`. | Existujúci povinný vstup treba doložiť. Voliteľnú sadu bez testov vypusti. |
| `{{testerCommand}}` | N | celý príkaz Nette Testera vrátane projektového wrappera, adresára a argumentov | bez Testera krok vynechaj |
| `{{phpstanCommand}}` | N S | úplný overený príkaz spúšťaný z koreňa projektu na hostiteľovi, vrátane wrappera alebo vstupu do kontajnera, konfigurácie, levelu, cieľov a ďalších argumentov. Ten istý príkaz použi v tabuľke aj v `run` s `runtime: host`. Cesty k binárke v kontajneri neposudzuj na hostiteľovi. | Ak je kontrola povinná a presný príkaz nepoznáš, zastav inštaláciu overovacích krokov a vyžiadaj si vstup. Onboarding môže skončiť inventárom. |
| `{{phpstanStopCommand}}` | N S | presný príkaz pre povolenú rýchlu spätnú väzbu s argumentom `{files}` a výstupom cesta:riadok | vynechaj celý voliteľný krok `phpstan-stop` |
| `{{composerAuditCommand}}` | N S | celý projektový príkaz nad lockfile spustiteľný z koreňa na hostiteľovi, aj keď volá kontajner. Bez wrappera použi `composer audit --locked --no-interaction --format=plain` v overenom runtime. | Pri povinnom audite bez bezpečne určiteľného príkazu alebo povolenia zastav aktiváciu. |
| `{{phpstanConfig}}` `{{phpstanLevel}}` | N S | skutočný príkaz harnessu alebo CI vrátane argumentov a zvoleného configu; zohľadni prípadný `--level` | bez PHPStan krok `phpstan` vypusti a v návrhu `AGENTS.md` zmaž jeho riadky a zmienky (Nástroje bez kroku); level zmaž |
| `{{mypyTarget}}` | P | `_init` v `devkit.json` | `.` |
| `{{packageManager}}` `{{installCommand}}` | P | lock súbor: `uv.lock` → uv, `uv sync`; `poetry.lock` → Poetry, `poetry install`; `requirements*.txt` → pip, `{{run}}pip install -r requirements.txt` | zmaž |
| `{{migrationTool}}` `{{migrateCommand}}` `{{migrateHealthyOutput}}` | P | `alembic.ini` → Alembic, `alembic upgrade head`; Django `manage.py` → `python manage.py migrate`, `No migrations to apply.` | zmaž |
| `{{package}}` | P | balík v `src/<balík>/` s `__init__.py` | riadok stromu uprav podľa repa |
| `{{entityDir}}` `{{repositoryDir}}` | N (Doctrine) | adresár tried s `#[ORM\Entity]`, resp. `extends EntityRepository`; do 0.3.x v `devkit.json` `entityGlob` = `{{entityDir}}**` | pair `doctrine-entity-migration` vypusti; zmaž |
| `{{migrationsDir}}` | N | Doctrine: prvá cesta z riadku migrácie Doctrine v kroku 1 (`migrations_paths`, nettrine `directories`/`directory`, `%appDir%` = adresár s `Bootstrap.php`); Phinx: prvá cesta z `paths.migrations` (krok 1); do 0.3.x `migrationsGlob` = `{{migrationsDir}}**` | Phinx s configom → otázka 4; Doctrine → pair `doctrine-entity-migration` vypusti; zmaž |
| `{{schemaValidateCmd}}` `{{migrationsCmd}}` | N (Doctrine) | krok 1 príkazy Doctrine | krok `doctrine-schema` vypusti; zmaž |
| `{{doctrineNeon}}` | N (Doctrine) | `*doctrine*.neon` v `app/config/` (krok 1 DB vrstva) | zmaž |
| `{{baseModel}}` | N (Dibi) | najčastejší rodič (`extends`) tried v `app/models/` | zmaž |
| `{{securedPresenter}}` | N | presenter, ktorého `startup()` overuje prihlásenie a ostatné ho dedia | zmaž riadok |
| `{{frontendStack}}` | N S | `package.json` (bundler, knižnice), commitnuté knižnice z kroku 1; S aj AssetMapper (`importmap.php`) alebo Webpack Encore z kroku 1 | zmaž riadok |
| `{{vendorFrontendPaths}}` | N S | krok 1 vendor kód (rovnaký zoznam ako `deny`); S aj `assets/vendor/` (AssetMapper) alebo `public/build/` (Encore) | `""` |
