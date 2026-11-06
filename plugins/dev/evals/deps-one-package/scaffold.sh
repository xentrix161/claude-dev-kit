#!/usr/bin/env bash
# Pracovný priestor prípadu: shop s composer.json, composer.lock a atrapou bin/composer (bez siete), vendor/ mimo gitu,
# CLAUDE.md s wrapperom composeru a vetvou s číslom úlohy.
exec bash "$(dirname "$0")/../fixtures/scaffold.sh" --extra deps --claude deps --branch chore/31-zavislosti \
  --first "[#30] feat: slug produktu cez acme/slugify"
