---
type: regex
target: { source: file, path: .git/COMMIT_EDITMSG }
pattern: '^\[#|^ABC-123 (feat|fix|refactor|chore|docs)[(:]'
match: not_contains
---
