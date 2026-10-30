---
description: "/dev:commit commitne jednoriadkovou správou s [#12] z vetvy, bez Co-Authored-By a bez push."
expected_outcome: "check.sh --auto PASS, git add konkrétnych súborov, commit „[#12] feat: …“ bez tela a bez AI atribúcie; žiadny git push, --no-verify ani --amend."
max_turns: 20
timeout_seconds: 600
allowed_tools: [Bash, Read, Grep, Glob]
---

/dev:commit návrh vopred schvaľujem — commitni hneď, bez ďalšej otázky
