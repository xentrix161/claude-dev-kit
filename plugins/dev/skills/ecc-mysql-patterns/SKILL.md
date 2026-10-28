---
name: ecc-mysql-patterns
description: "MySQL 5.7/8 v PHP (Dibi, Doctrine, Phinx): parametre, indexy, EXPLAIN, N+1, transakcie, triggery, migrácie. Pri návrhu schémy, pomalom dotaze a review SQL."
paths:
  - "db/**"
  - "migrations/**"
  - "**/*Model.php"
  - "**/*.sql"
  - "src/Repository/**"
---
<!-- prevzaté z ECC skills/mysql-patterns/SKILL.md @ b92f181, upravené -->

# MySQL vzory (Dibi · Doctrine · Phinx)

## Kedy
- návrh tabuliek, indexov a migrácií (Phinx `db/migrations/`, Doctrine `migrations/`)
- pomalý dotaz, lock wait, deadlock, N+1 v modeli alebo repozitári
- review SQL v `*Model.php`, `src/Repository/**`, `*.sql`

## Krok 0 — verzia
- `SELECT VERSION();` — 5.7 a 8.0 sa líšia, MariaDB je tretí dialekt (syntax over zvlášť)
- Doctrine: `server_version` v `config/packages/doctrine.yaml` musí sedieť s reálnou DB, inak DBAL generuje SQL aj diff migrácií pre inú platformu

| Funkcia | 5.7 | 8.0 |
|---|---|---|
| CTE `WITH`, okenné funkcie | nie | áno |
| `FOR UPDATE SKIP LOCKED` / `NOWAIT` | nie | áno |
| `EXPLAIN ANALYZE` (dotaz **vykoná**) | nie → `EXPLAIN FORMAT=JSON` | 8.0.18+ |
| upsert alias `VALUES (…) AS new` | nie → `VALUES(col)` | 8.0.19+ (`VALUES()` deprecated od 8.0.20) |
| funkčný index | generovaný stĺpec + index | 8.0.13+ |
| `DESC` v indexe | parsuje sa, ignoruje | skutočný |
| neviditeľný index | nie | `ALTER TABLE t ALTER INDEX i INVISIBLE` |
| `ALGORITHM=INSTANT` pri `ADD COLUMN` | nie | 8.0.12+ |
| predvolená collation `utf8mb4` | `utf8mb4_general_ci` | `utf8mb4_0900_ai_ci` (v 5.7 neexistuje → pozor na dump 8 → 5.7) |

## Parametre — nikdy reťazec
- Dibi: modifikátory, nie `.`
  - `$db->query('SELECT … WHERE id = %i AND name = %s', $id, $name)`; `?` funguje tiež
  - pole: `WHERE id IN %in` (prázdne pole → `IN (NULL)`, nič nevráti); `%l` s prázdnym poľom = SQL chyba
  - podmienky: `WHERE %and`, `['status' => $s, 'deleted_at' => null]` (`null` → `IS NULL`)
  - LIKE: `%like~` (začína na), `%~like~` (obsahuje) — escapujú `%` a `_`
  - meno stĺpca (napr. `ORDER BY` z requestu): `%n` + hodnota z whitelistu; `%SQL`/`%ex` vkladajú surové SQL — len konštanty
  - fluent: `$db->select('id')->from('t')->where('x = %i', $x)->fetchAll()`
- Doctrine DBAL 4: `$conn->executeQuery('… WHERE id IN (?)', [$ids], [ArrayParameterType::INTEGER])`; DQL/QueryBuilder `->setParameter('id', $id)`
- Phinx: `$this->execute('UPDATE t SET a = ? WHERE id = ?', [$a, $id])`
- `LIMIT`/`OFFSET` z requestu: ako int (`%i`, `ParameterType::INTEGER`)

## Schéma — predvoľby
| Na čo | Áno | Nie |
|---|---|---|
| engine, znaky | `InnoDB`, `utf8mb4` | MyISAM, `utf8` (= utf8mb3, bez emoji) |
| peniaze, presné čísla | `DECIMAL(p,s)` | `FLOAT`, `DOUBLE` |
| čas | `DATETIME` s dohodnutou zónou | `TIMESTAMP` pre dátumy mimo 1970–2038 |
| PK | `INT/BIGINT UNSIGNED AUTO_INCREMENT` | `VARCHAR(36)` UUID ako PK zaťaženej tabuľky |
| meniace sa stavy | číselníková tabuľka + FK | `ENUM` (zmena hodnoty = `ALTER` celej tabuľky) |
| stĺpce v JOIN | rovnaký typ aj collation na oboch stranách | rozdiel → index sa nepoužije |
- stĺpec, cez ktorý sa JOINuje bez FK, potrebuje vlastný index (InnoDB ho vytvorí sám len pri FK)
- 5.7 + `ROW_FORMAT=COMPACT`: index nad `utf8mb4 VARCHAR(>191)` padne (limit 767 B) → `DYNAMIC` alebo prefixový index

## Indexy
- zložený index: najprv stĺpce s rovnosťou, potom jeden stĺpec s rozsahom alebo triedením — za rozsahom index už nezúži hľadanie ani neušetrí `filesort`
- platí ľavý prefix: `(a,b,c)` pomôže `a`, `a,b`, `a,b,c`, nie `b`
- index zabije:
  - funkcia nad stĺpcom: `DATE(created_at) = ?` → `created_at >= ? AND created_at < ?`
  - implicitná konverzia: `varchar_col = 123` → porovnávaj reťazcom
  - `LIKE '%x'`
  - `OR` cez rôzne stĺpce (keď `EXPLAIN` neukáže `index_merge`) → `UNION` dvoch indexovaných dotazov; `UNION ALL` len keď sa vetvy neprekrývajú; komentár „nezlučovať späť do OR — znemožní index"
  - rozdielna collation/typ v JOINe
- pokrývajúci index (všetky stĺpce dotazu v indexe) → `Extra: Using index`
- index nepridávaj naslepo: spomaľuje zápis aj migráciu → najprv `EXPLAIN`
- nepoužívaný index na 8.0 najprv `INVISIBLE`, až potom `DROP`

## EXPLAIN
- na dev DB s realistickým objemom dát: projektový príkaz (`make db-shell`, Adminer) alebo `docker exec -i <db-kontajner> mysql … -e "EXPLAIN …"`; heslo nevypisuj
- `EXPLAIN ANALYZE` dotaz vykoná → len `SELECT` a len na dev

| Pole | Signál problému |
|---|---|
| `type` | `ALL` (full scan) na veľkej tabuľke; `index` = sken celého indexu |
| `key` | `NULL`, hoci existuje selektívna podmienka |
| `rows` × `filtered` | vysoký odhad v interaktívnej ceste |
| `Extra` | `Using temporary`, `Using filesort`, `Using join buffer` |
- výstupy EXPLAIN, časy a počty riadkov patria do odpovede alebo PR, nie do komentára v kóde

## N+1
- príznak: dotaz v cykle (`foreach` → `$model->getX($row->id)`); Tracy panel / Symfony profiler ukazuje desiatky podobných dotazov
- Dibi: jeden dotaz `WHERE parent_id IN %in` + `fetchAssoc('parent_id[]')`, spojenie v PHP
- Nette Database Explorer (`$row->related()`) dávkuje sám — Dibi nie
- Doctrine: fetch join `->leftJoin('o.items', 'i')->addSelect('i')`; `fetch: 'EXTRA_LAZY'` pre `count()` nad kolekciou; veľké dávky `toIterable()` + `$em->clear()`; `flush()` mimo cyklu
- pri väčšom diffe deleguj na agenta `dev:ecc-performance-optimizer`

## Dotazy
```sql
-- upsert 5.7 / MariaDB
INSERT INTO t (user_id, k, v) VALUES (?, ?, ?)
ON DUPLICATE KEY UPDATE v = VALUES(v);
-- upsert 8.0.19+
INSERT INTO t (user_id, k, v) VALUES (?, ?, ?) AS new
ON DUPLICATE KEY UPDATE v = new.v;
```
- upsert spustí `BEFORE INSERT` aj `UPDATE` triggery a minie hodnotu `AUTO_INCREMENT` aj pri update
- stránkovanie veľkých tabuliek: keyset namiesto hlbokého `OFFSET`
  `WHERE created_at < ? OR (created_at = ? AND id < ?) ORDER BY created_at DESC, id DESC LIMIT 50` + index `(created_at, id)`
- JSON stĺpec (5.7.8+) len na rozširujúce dáta; filtrovanú cestu vytiahni do generovaného stĺpca s indexom

## Transakcie
- krátke; zámky v rovnakom poradí (`… ORDER BY id FOR UPDATE`); žiadne HTTP/API volania vnútri
- transakciu otvára volajúci (presenter, service, command), nie model/repozitár: `START TRANSACTION` v otvorenej transakcii ju **ticho commitne** a rozbije aj rollback v integračných testoch (Doctrine `beginTransaction()` vnorenie zvláda, Dibi `begin()` bez mena savepointu nie)
- DDL (`CREATE/ALTER/DROP`) robí implicitný commit → migrácia v MySQL nie je atomická; Doctrine migrácia s DDL: `isTransactional(): bool { return false; }`
- deadlock: rollback + zopakovať celú transakciu s limitom pokusov; hneď potom `SHOW ENGINE INNODB STATUS\G` (sekcia o poslednom deadlocku sa prepisuje)
- `SKIP LOCKED` (8.0) len pre fronty úloh, nie pre konzistentné čítanie

## Triggery a dáta ako kontrakt
- trigger beží v tej istej transakcii a v PHP ho nevidno → pred zmenou tabuľky `SHOW TRIGGERS LIKE 'tabuľka%'`
- MySQL nemá `CREATE OR REPLACE TRIGGER` (MariaDB áno) → `DROP TRIGGER IF EXISTS` + `CREATE TRIGGER` v jednej migrácii
- premenovanie tabuľky/stĺpca: hľadaj aj dáta, ktoré nesú jeho meno (audit log, stĺpec s názvom tabuľky, serializované objekty) — staré záznamy sa nepreložia samy a chyba sa ukáže až pri spätnom použití

## Migrácie
- commitnutá alebo aplikovaná migrácia sa neupravuje → nová migrácia
- veľká tabuľka: uveď `ALGORITHM=INPLACE, LOCK=NONE` (8.0 pri `ADD COLUMN` `ALGORITHM=INSTANT`) — keď to nejde, príkaz zlyhá namiesto tichého kopírovania tabuľky pod zámkom
- backfill po dávkach (`WHERE id BETWEEN ? AND ?`), nie jeden `UPDATE` celej tabuľky
- pred spustením: suchý beh na kópii DB, záloha, návratový postup (DDL rollback nevráti)
- Phinx: `change()` len pre reverzibilné operácie; dátové kroky v `up()`/`down()` cez `execute($sql, $params)`

## Pasce
- Dibi 4+: `fetch()`/`fetchSingle()` bez riadku vracia `null`, nie `false` → `=== false` nikdy neplatí
- Dibi 4+: dátumy sú `Dibi\DateTime extends \DateTimeImmutable` → `instanceof \DateTime` ticho zlyhá, kontroluj `\DateTimeInterface`
- `ONLY_FULL_GROUP_BY` (predvolené od 5.7.5): ne-agregovaný stĺpec patrí do `GROUP BY` — oprav dotaz, nevypínaj `sql_mode`
- Doctrine `flush()` v cykle = dotaz na každý riadok → hromadne cez DQL `UPDATE` alebo dávky

## Diagnostika
- `SHOW FULL PROCESSLIST;` — čo beží a na čo čaká
- `SHOW ENGINE INNODB STATUS\G` — zámky a deadlocky
- slow log na dev: `SET GLOBAL slow_query_log = 'ON'; SET GLOBAL long_query_time = 1;`
- `sys.schema_unused_indexes`, `sys.statements_with_full_table_scans` (5.7.7+, vyžaduje performance_schema)

## Bezpečnosť
- runtime používateľ appky: `SELECT, INSERT, UPDATE, DELETE` na vlastnú DB; migrácie a triggery iným používateľom
- žiadne `GRANT ALL`, `*.*`, anonymní používatelia
- prihlasovacie údaje len v lokálnom configu (`config.local.neon`, `.env.local`), nie v repozitári, príkladoch ani výstupe

## Anti-vzory
| Anti-vzor | Lepšie |
|---|---|
| `SELECT *` v často volanej ceste | vymenované stĺpce |
| SQL skladané reťazcom | parametre / modifikátory |
| dotaz v cykle | `IN %in` + spojenie v PHP, fetch join |
| hlboký `OFFSET` | keyset stránkovanie |
| dlhá transakcia, API volanie v nej | malé jednotky práce |
| `ENUM` pre meniace sa hodnoty | číselník |

## Výstup (review / návrh)
- prvý riadok: záver (bezpečné / riziko / blokujúce) + predpoklad verzie (5.7 / 8.0 / MariaDB)
- nálezy `súbor:riadok — problém → oprava`; poradie: správnosť, zámky, bezpečnosť, migrácie, výkon
- presné SQL/PHP pre bezpečnú cestu
- overenie: `EXPLAIN` pred a po, suchý beh migrácie, návratový postup
