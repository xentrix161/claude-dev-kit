---
description: "/dev:fix napíše padajúci regresný test, zamkne ho cez test-lock.sh a opraví kód bez zmeny testu."
expected_outcome: "Test s price_with_vat 199 → 239 najprv padne, test-lock.sh lock pred úpravou lib/price.sh, oprava zaokrúhlenia v lib/price.sh, check.sh --auto PASS, odomknutie; test sa po zamknutí nemení."
max_turns: 40
timeout_seconds: 900
allowed_tools: [Bash, Read, Grep, Glob, Edit, Write]
---

/dev:fix price_with_vat 199 vráti 238, správne je 239 — cena s DPH sa má zaokrúhliť na najbližší cent, nie nadol
