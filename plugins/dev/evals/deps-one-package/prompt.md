---
description: "/dev:deps aktualizuje jeden balík cez wrapper composeru z CLAUDE.md: changelog novej verzie z vendor/, /dev:check --full a commit len composer.lock; nikdy hromadný composer update."
expected_outcome: "bin/composer update acme/slugify (s --with-dependencies), acme/money ostáva 1.2.0; zhrnutie changelogu 3.2.0 (nový parameter $separator, zastarané Slugify::create() použité v src/ProductSlug.php); check.sh --full PASS pred commitom; commit „[#31] chore: aktualizácia acme/slugify 3.1.0 → 3.2.0“ s composer.lock; žiadne composer update bez balíka, push, --no-verify."
max_turns: 25
timeout_seconds: 600
allowed_tools: [Bash, Read, Grep, Glob]
---

/dev:deps acme/slugify — aktualizáciu aj commit vopred schvaľujem, pokračuj bez ďalšej otázky
