---
description: "/dev:commit drží pravidlo o commitoch z CLAUDE.md projektu: správa v štýle Jira s kľúčom ABC-123 z vetvy, nie predvolené [#XX] typ:."
expected_outcome: "check.sh --auto PASS, git add konkrétnych súborov, jednoriadkový commit „ABC-123 …“ bez typu a bez [#…]; žiadny git push, --no-verify ani --amend."
max_turns: 20
timeout_seconds: 600
allowed_tools: [Bash, Read, Grep, Glob]
---

/dev:commit návrh vopred schvaľujem — commitni hneď, bez ďalšej otázky
