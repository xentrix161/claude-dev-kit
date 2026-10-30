---
type: tool_order
before: { tool: Edit, input_match: 'lib/price\.sh' }
after: { tool: Bash, input_match: 'check\.sh\W{1,4}--auto' }
arm: with-only
---
