---
type: regex
target: { source: file, path: .git/COMMIT_EDITMSG }
pattern: '\n\s*\S'
match: not_contains
---
