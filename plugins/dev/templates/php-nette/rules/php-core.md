---
paths:
  - "**/*.php"
---

# PHP — základ

- Štýl okolitého kódu má prednosť pred osobnými preferenciami; nové vzory nezavádzaj bez dohody.
- PSR-12 (phpcs ho stráži na pridaných riadkoch); `[]` namiesto `array()`.
- `declare(strict_types=1)` len tam, kde ho súbor alebo projekt už používa.
- Typy všade, kde ich PHP dovolí: parametre, návratové hodnoty, vlastnosti; nie `@var` namiesto typu.
- Porovnania `===` / `!==`; `in_array($x, $pole, true)`.
- Chyby hádž konkrétnou výnimkou; `catch` len to, čo vieš ošetriť, a nikdy prázdny.
- Logovanie cez Tracy (`Tracy\Debugger::log()`, `Tracy\ILogger`), nie `error_log()` ani `echo`.
- Závislosti cez konštruktor (constructor promotion, ak ju projekt používa).
- PHPStan: nové chyby oprav; baseline sa regeneruje len na pokyn, `@phpstan-ignore` len s dôvodom.

## Zakázané

- debug výpisy `dump()`, `dd()`, `bdump()`, `var_dump()`, `print_r()` — hook ich hlási
- `die()` / `exit()` → `throw` alebo `$this->terminate()`
- potlačenie chýb operátorom `@` → over podmienku alebo chyť výnimku
- SQL skladané reťazcom → parametre Dibi (`db-dibi.md`)

## Komentáre

- Krátke alebo žiadne; max 3–4 riadky nad metódou, drž hustotu okolitého súboru.
- Len to, čo z kódu nevidno a čo bráni regresii („nezlučovať do `OR`, znemožní index").
- Žiadne merania, časy, počty riadkov, výstupy `EXPLAIN`, produkčné dáta ani odkazy na konkrétne záznamy.
- Žiadna história („pôvodne…", „prvá verzia…") ani stopa po tom, ako sa k riešeniu prišlo.
- Sémantiku drží test — odkáž naň jednou vetou.

## Pasce

- `'1e3' == '1000'` je `true` (numerické reťazce) → `===`, najmä pri kódoch a ID.
- `empty('0')` je `true` a `array_filter($a)` bez callbacku zahodí `'0'` aj `0` — formulárové hodnoty sa stratia.
- `json_encode()`/`json_decode()` pri chybe nehádžu → `JSON_THROW_ON_ERROR` alebo `Nette\Utils\Json`.
- `catch (\Exception)` zhltne aj `AbortException` z `redirect()` (`nette.md`).
- `DateTimeImmutable::modify()` vracia nový objekt — bez priradenia sa nič nezmení.
- Float pri peniazoch a percentách nie je presný (`0.1 + 0.2 !== 0.3`) → porovnávaj po `round()` alebo počítaj v celých číslach (centy).
- `static` cache vo vlastnosti prežije celý request aj CLI job — po zmene dát vracia staré hodnoty.
