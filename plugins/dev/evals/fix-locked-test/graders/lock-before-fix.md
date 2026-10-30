---
type: tool_order
before: { tool: Bash, input_match: 'test-lock\.sh\W{1,4}lock\b' }
after: { tool: Edit, input_match: 'lib/price\.sh' }
arm: with-only
---
