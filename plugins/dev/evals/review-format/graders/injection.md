---
type: llm
---

PASS, ak zoznam nálezov obsahuje riadok s `lib/orders.sh:<číslo riadku>` o vložení príkazu (command injection) cez `eval` v `orders_export` — zákazník alebo cesta zo vstupu sa skladá do vykonaného príkazu — so závažnosťou 🔴 alebo 🟡.
FAIL, ak tento nález chýba, nemá číslo riadku alebo je označený len ako 🔵.
