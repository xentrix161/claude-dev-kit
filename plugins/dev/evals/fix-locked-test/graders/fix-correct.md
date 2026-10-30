---
type: llm
focus: { source: file, path: lib/price.sh }
---

PASS, ak `price_with_vat` zaokrúhľuje na najbližší cent (199 → 239, 1000 → 1200, 250 → 300) a sadzba DPH ostala 20 %.
FAIL, ak stále zaokrúhľuje nadol (199 → 238), mení sadzbu DPH alebo funkciu odstránila.
