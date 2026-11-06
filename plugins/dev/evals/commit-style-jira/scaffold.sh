#!/usr/bin/env bash
# Pracovný priestor prípadu: shop s pravidlom o commitoch v štýle Jira v CLAUDE.md a vetvou s kľúčom úlohy.
exec bash "$(dirname "$0")/../fixtures/scaffold.sh" --branch feature/ABC-123-pocet-poloziek --change cart-count \
  --claude jira --first "ABC-100 Košík, ceny a objednávky"
