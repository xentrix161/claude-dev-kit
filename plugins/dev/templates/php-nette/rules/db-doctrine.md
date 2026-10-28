---
paths:
  - "**/Entity/**"
  - "**/Repository/**"
  - "**/*Repository.php"
  - "migrations/**"
  - "app/config/*doctrine*.neon"
---

# Databáza — Doctrine ORM a Doctrine Migrations v Nette

## Entity a dotazy

- Mapovanie atribútmi (`#[ORM\Entity]`, `#[ORM\Column]`) — žiadne docblock anotácie ani nové XML/YAML mapovanie.
- Dotazy len v repozitároch; hodnoty vždy cez `setParameter()` / DBAL `?`, `:name`, nikdy reťazcom; dynamické názvy polí len z whitelistu.
- `find()` / `findOneBy()` vráti `null`, nie výnimku — ošetri pred použitím.
- Typy `datetime_immutable`, `date_immutable`; nullable stĺpec = nullable typ v PHP.
- Doctrine sa registruje v neon configu (vlastná extension alebo nettrine) — služby do tried idú konštruktorom, `EntityManager` nie je globálny.

## Transakcie a výkon

- Transakciu riadi volajúci (služba, presenter, command) cez `wrapInTransaction()`, nie repozitár.
- N+1: vzťahy pre cyklus načítaj `JOIN … addSelect()` alebo dávkovo jedným dotazom (`WHERE x IN (:ids)`).
- Hromadné zmeny v dávkach s `flush()` + `clear()`; veľké úpravy cez DQL `UPDATE`/DBAL.

## Migrácie

- Príkazy konzoly podľa projektu: `doctrine:migrations:*` alebo pri nettrine `migrations:*` — presný tvar je v `CLAUDE.md`/`AGENTS.md`.
- Zmena entity → spýtaj sa na migráciu (`migrations:diff`); bez súhlasu ju nevytváraj. Vygenerované `up()` aj `down()` skontroluj (odstránenia, premenovania, zachovanie dát).
- Vydanú migráciu ani jej vstupy neprepisuj — vytvor novú (hook sa pred úpravou pýta).
- `migrations:migrate` len na výslovný pokyn — aj s `--dry-run`, môže založiť tabuľku histórie migrácií.
- Nie `schema:update --force` ani `orm:schema-tool:update` namiesto migrácie.

## Overenie

- `doctrine:schema:validate` (nettrine: `orm:validate-schema`) → `[OK] The mapping files are correct.` + `[OK] The database schema is in sync with the mapping files.`
- `migrations:status` / `migrations:up-to-date` ukážu čakajúce migrácie; len čítajú.
- Po zmene entity alebo neon configu vyčisti cache appky (metadáta mapovania sú v nej) — inak validácia aj appka bežia so starým mapovaním.

## Pasce

- `schema:validate` porovná len to, čo ORM pozná — natívne objekty (triggery, views, procedúry) neoverí.
- `migrations:diff` pridá nesúvisiace `RENAME INDEX` (drift hash názvov indexov) → z `up()` aj `down()` ich vymaž, nechaj len zamýšľanú zmenu.
- Entita z cache (result cache, serializovaná) je detached: setter + `flush()` ticho nič nezapíše → načítaj ju znovu alebo zapisuj cez DBAL.
- DQL `UPDATE` a DBAL obchádzajú UnitOfWork: listenery ani lifecycle callbacky sa nespustia → vyvolaj ich sám.
- `NOW()` v SQL beží v časovej zóne DB, PHP môže mať inú → čas binduj z PHP.
- `flush()` v cykle po jednom riadku = tisíce dotazov a rastúca pamäť → dávka + `clear()`.
- Premenovanie tabuľky alebo stĺpca rozbije všetko, čo naň odkazuje reťazcom (raw SQL, triggery, exporty) → najprv grep.
