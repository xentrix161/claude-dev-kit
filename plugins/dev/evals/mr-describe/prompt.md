---
description: "/dev:mr pripraví popis PR vetvy so sekciami Čo, Prečo, Ako overiť, Riziká, Po nasadení: migrácia a premenná prostredia z diffu, verdikt /dev:check z pass.json, review agentmi; bez remote nič nevytvára a nepushuje."
expected_outcome: "Názov s [#42] a popis v bloku markdown so všetkými piatimi sekciami; Prečo z plánu docs/plans/42-zlava-objednavky.md; Ako overiť s /dev:check --full PASS; Po nasadení s migráciou db/migrations/20261101120000_orders_discount.sql a premennou SHOP_MAX_DISCOUNT_PERCENT; agenti ecc-pr-test-analyzer a ecc-silent-failure-hunter nad diffom main...HEAD; bez gh, glab a git push — vetva nie je na origin."
max_turns: 25
timeout_seconds: 900
allowed_tools: [Bash, Read, Grep, Glob, Agent]
---

/dev:mr
