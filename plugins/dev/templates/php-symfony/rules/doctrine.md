---
paths:
  - "src/Entity/**"
  - "src/Repository/**"
  - "src/DataFixtures/**"
  - "migrations/**"
  - "config/packages/doctrine*.yaml"
---

# Doctrine ORM a migrácie

- Mapovanie atribútmi (`#[ORM\Entity]`, `#[ORM\Column]`) — žiadne docblock anotácie ani nové XML/YAML mapovanie.
- Dotazy len v repozitároch; hodnoty vždy cez `setParameter()` / DBAL `?`, `:name`, nikdy reťazcom; dynamické názvy polí len z whitelistu.
- Zmena entity → spýtaj sa na migráciu (`doctrine:migrations:diff`); bez súhlasu ju nevytváraj (Stop hook to pripomenie).
- Commitnutú migráciu neupravuj — vytvor novú (hook sa pýta); `down()` musí vrátiť presne to, čo urobil `up()`.
- Nie `doctrine:schema:update --force` namiesto migrácie; `doctrine:fixtures:load` bez `--append` vymaže dáta v DB.
- N+1: vzťahy pre cyklus načítaj `JOIN … addSelect()` alebo dávkovo jedným dotazom (`WHERE x IN (:ids)`).
- Hromadné zmeny v dávkach s `flush()` + `clear()`; veľké úpravy cez DQL `UPDATE`/DBAL.
- Typy `datetime_immutable`, `date_immutable`; nullable stĺpec = nullable typ v PHP.
- Transakciu riadi volajúci (služba, command) cez `wrapInTransaction()`, nie repozitár.
- `find()`/`findOneBy()` vráti `null`, nie výnimku — ošetri pred použitím.

## Overenie

- `bin/console doctrine:schema:validate` → `[OK] The mapping files are correct.` + `[OK] The database schema is in sync with the mapping files.`
- Lokálna DB zaostáva → `doctrine:migrations:migrate` alebo dočasne `--skip-sync`; `doctrine:migrations:status` ukáže, čo chýba.

## Pasce

- `doctrine:migrations:diff` pridá nesúvisiace `RENAME INDEX` (drift hash názvov indexov) → z `up()` aj `down()` ich vymaž, nechaj len zamýšľanú zmenu.
- Entita z cache (result cache, serializovaná) je detached: setter + `flush()` ticho nič nezapíše → načítaj ju znovu alebo zapisuj cez DBAL.
- DQL `UPDATE` a DBAL obchádzajú UnitOfWork: listenery, lifecycle callbacky ani invalidácia cache sa nespustia → vyvolaj ich sám.
- `NOW()` v SQL beží v časovej zóne DB (často UTC), PHP môže mať inú → čas binduj z PHP.
- Dátová migrácia nemá služby appky (listenery, trackery) → vedľajšie efekty (changelog, metadáta) zapíš v nej explicitne.
- `flush()` v cykle po jednom riadku = tisíce dotazov a rastúca pamäť → dávka + `clear()`.
- Premenovanie tabuľky alebo stĺpca rozbije všetko, čo naň odkazuje reťazcom (raw SQL, triggery, logy, exporty) → najprv grep.
