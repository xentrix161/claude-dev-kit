---
paths:
  - "tests/**"
  - "phpunit.xml*"
  - "phpunit.dist.xml"
  - ".env.test"
---

# Testy (PHPUnit)

- Spúšťaj cez `/dev:check` alebo príkaz z `.claude/devkit.json` (v kontajneri, bez `-it`); hotovo = výstup `OK (… tests, … assertions)`, nie tvrdenie.
- Oprava bugu: najprv test, ktorý chybu zachytí a padá zo správneho dôvodu, potom oprava kódu (`/dev:fix` test zamkne).
- Štruktúra zrkadlí `src/` (`src/Service/Foo.php` → `tests/Service/FooTest.php`); AAA (Arrange, Act, Assert), jeden dôvod zlyhania na test.
- Metadáta len atribútmi: `#[Test]`, `#[DataProvider]`, `#[CoversClass]`, `#[Group]`; data providery `public static`.
- `createStub()` pre závislosť bez očakávaní, `createMock()` len keď overuješ volanie.
- Unit testy bez DB a siete; služby z kontajnera v `KernelTestCase` cez `static::getContainer()` (vidí aj privátne služby).
- Funkčné testy: `WebTestCase` + `static::createClient()`, `assertResponseIsSuccessful()`, `assertSelectorTextContains()`.
- DB testy: oddelená testovacia DB (`.env.test`, `dbname_suffix`) a izolácia transakciou (DAMA DoctrineTestBundle) alebo resetom (Foundry `ResetDatabase`).
- Mail v teste nikam neodchádza (`MAILER_DSN=null://null`); over ho cez `assertEmailCount()`.
- Test nevypínaj, aby check prešiel (`markTestSkipped`, zmazaná metóda, oslabený assert) — oprav kód alebo sa spýtaj.

## Overenie

- `php vendor/bin/phpunit` → `OK (… tests, … assertions)`; jeden test `--filter testNazov`, jeden súbor cestou.
- Stop kontrola púšťa celú sadu → pomalé testy (DB, HTTP) daj do samostatnej `<testsuite>` a v `devkit.json` do kroku len s režimom `full`.

## Pasce

- PHPUnit 12+ docblock anotácie (`@dataProvider`, `@group`, `@covers`) ignoruje → test beží bez dát alebo mimo skupiny.
- Premenné z `environment:` v docker compose prebijú `.env.test` (Dotenv reálne env neprepisuje) → over, ktorú DB testy naozaj používajú.
- Lokálny `phpunit.xml` (ignorovaný) má prednosť pred `phpunit.xml.dist`/`phpunit.dist.xml` → iné sady než v CI.
- `KernelBrowser` medzi requestmi reštartuje kernel → podvrhnutá služba z kontajnera zmizne; `$client->disableReboot()`.
- `.env.local` sa v teste nenačíta, `.env.test.local` áno → lokálne nastavenie testov patrí tam.
- Počty testov nepíš do dokumentácie — zastarávajú; zdravý výstup je tvar, nie číslo.
