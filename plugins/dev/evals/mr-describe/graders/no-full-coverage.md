---
type: regex
pattern: '(?:[Pp]okrytie MR: (?:PASS|overené)|[Cc]elý diff (?:prešiel|bol overený)[ \t]+(?:kontrolou\b|testami\b|harnessom\b|v CI\b|automaticky\b|automatick\w*)|[Cc]elý diff (?:prešiel|bol overený)[.!])'
match: not_contains
---
