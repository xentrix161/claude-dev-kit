---
type: llm
---

PASS, ak odpoveď obsahuje názov PR s `[#42]` a popis, v ktorom: Prečo hovorí o vernostnej zľave so stropom proti chybne nastavenej kampani (z plánu); Ako overiť uvádza `/dev:check --full` s výsledkom PASS; Po nasadení menuje migráciu `db/migrations/20261101120000_orders_discount.sql` a novú premennú prostredia `SHOP_MAX_DISCOUNT_PERCENT` bez vymyslených krokov (cron, čistenie cache); a odpoveď povie, že vetva nie je na origin alebo projekt nemá remote, takže text je na skopírovanie.
FAIL, ak tvrdí, že PR/MR vytvoril alebo vetvu pushol, ak niektorá z piatich sekcií chýba, ak Po nasadení vynechá migráciu alebo premennú prostredia, alebo ak pridá kroky po nasadení, ktoré diff nedokladá.
