---
paths:
  - "db/**"
  - "migrations/**"
  - "app/models/**"
  - "app/model/**"
  - "app/Model/**"
  - "**/*Model.php"
  - "phinx.php"
  - "phinx.json"
  - "phinx.yaml"
  - "phinx.yml"
---

# Databáza — Dibi 4+ a Phinx

## Dotazy

- Hodnoty len cez modifikátory: `%s`, `%i`, `%f`, `%b`, `%d`/`%t`, `%in`, `%and`, `%or`, `%n` (identifikátor) alebo `?`.
- `LIKE` cez `%like~` (začína), `%~like` (končí), `%~like~` (obsahuje) — escapujú `%` a `_`; nie `'%' . $x . '%'`.
- Stĺpec a smer pre `ORDER BY` zo vstupu → whitelist; `%n` zo vstupu nie je ochrana.
- `fetch()` aj `fetchSingle()` vracajú `null`, keď nič nenájdu (nie `false`) → `=== null`.
- Dátumy sú `Dibi\DateTime` (`DateTimeImmutable`) → typuj `\DateTimeInterface`.
- `fetchPairs()` / `fetchAssoc('id')` namiesto skladania polí v cykle.

## Transakcie

- V modeloch **nikdy** `$db->begin()` / `commit()` / `rollback()` — transakciu otvára volajúci (presenter, služba, CLI príkaz).
- Dôvod: MySQL `BEGIN` implicitne commitne otvorenú transakciu → integračné testy (begin/rollback) by zapisovali natrvalo.
- DDL (`CREATE`, `ALTER`, `DROP`, `TRUNCATE`) tiež implicitne commitne — nepatrí do kódu, ktorý volá test.

## Migrácie (Phinx)

- Každá zmena schémy, číselníka alebo triggera = nová migrácia (`YYYYMMDDHHMMSS_nazov.php`) v adresári z `paths.migrations` konfigurácie Phinx (predvolene `db/migrations/`).
- Aplikovanú alebo commitnutú migráciu **neupravuj** — chybu oprav novou migráciou (hook sa pred úpravou pýta).
- `phinx migrate`, `rollback` a `seed:run` len na výslovný pokyn (menia DB).
- Vždy funkčný návrat: `down()`, alebo `change()` len s operáciami, ktoré Phinx vie vrátiť (`up()`/`down()` vedľa `change()` ignoruje); dátové migrácie idempotentné.
- Zmena modelu alebo tabuľky bez migrácie → opýtaj sa, či ju používateľ chce.
- Zmena stĺpcov tabuľky s triggermi → skontroluj triggery (`SHOW TRIGGERS LIKE 'tabuľka'`).

## Výkon

- N+1 (dotaz v cykle cez riadky) → jeden dotaz s `IN %in` a `fetchAssoc()`; navrhni, nevnucuj.
- Nový filter alebo `JOIN` na veľkej tabuľke → over `EXPLAIN` a index.

## Pasce

- `if ($row === false)` po `fetch()` je vždy nepravda — chýbajúci záznam prejde ďalej ako `null`.
- `instanceof \DateTime` na hodnote z Dibi je vždy `false` (ticho) a `->modify()` bez priradenia nič nezmení.
- `%and` / `%or` s prázdnym poľom vygeneruje `1=1` → `UPDATE`/`DELETE` s prázdnym filtrom zasiahne celú tabuľku.
- `%in` s prázdnym poľom vygeneruje `IN (NULL)` = žiadny riadok; ošetri prázdny vstup pred dotazom.
- `WHERE stĺpec = %s` s `null` nič nenájde → `%and` s poľom (`IS NULL`) alebo explicitné `IS NULL`.
- MySQL 5.7 nemá CTE (`WITH`) ani window funkcie; `ONLY_FULL_GROUP_BY` odmietne neagregovaný stĺpec mimo `GROUP BY`.
- MySQL DDL nie je transakčné — migrácia, ktorá padne v polovici, ostane napoly; rob malé kroky.
