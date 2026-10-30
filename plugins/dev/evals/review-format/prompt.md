---
description: "/dev:review vypíše nálezy v predpísanom riadkovom formáte so súbor:riadok a súhrnným riadkom."
expected_outcome: "Nálezy „<emoji> N. lib/orders.sh:<riadok> — …“: vloženie príkazu cez eval v orders_export a vynechaný posledný riadok v orders_sum; na konci „X critical, Y warning, Z suggestions“; žiadna úprava súborov."
max_turns: 15
timeout_seconds: 300
allowed_tools: [Bash, Read, Grep, Glob]
---

/dev:review
