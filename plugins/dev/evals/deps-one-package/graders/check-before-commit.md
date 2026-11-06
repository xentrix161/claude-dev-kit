---
type: tool_order
before: { tool: Bash, input_match: 'check\.sh[^"]*--full' }
after: { tool: Bash, input_match: 'git\s+commit' }
arm: with-only
---
