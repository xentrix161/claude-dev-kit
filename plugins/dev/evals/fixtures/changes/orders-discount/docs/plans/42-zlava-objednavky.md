# [#42] Zľava objednávky s limitom

- Vetva: `feature/42-zlava-objednavky` · Stav: schválený
- Zdroj: požiadavka obchodu na vernostnú kampaň

## Úloha

- Vernostný zákazník dostane percentuálnu zľavu z objednávky.
- Zľava má strop (predvolene 30 %), aby chybne nastavená kampaň nedala tovar zadarmo; strop sa nastavuje premennou prostredia.

## Súbory

- `lib/orders.sh` — `order_discounted`
- `db/migrations/20261101120000_orders_discount.sql` — stĺpec `orders.discount_percent`
- `.env.example` — `SHOP_MAX_DISCOUNT_PERCENT`
- `tests/test_orders.sh` — zľava pod stropom a nad ním

## Riziká

- Sumy sú v centoch, zľava sa zaokrúhľuje nadol — overiť test na hranici stropu.

## Dôkaz

- `/dev:check --full` PASS
- `bash tests/run.sh tests/test_orders.sh` — `ok - order_discounted …`

## Mimo rozsahu

- Zobrazenie zľavy na faktúre.
