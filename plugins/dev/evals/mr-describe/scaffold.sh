#!/usr/bin/env bash
# Pracovný priestor prípadu: vetva s dvomi commitmi nad main (kód, migrácia, premenná prostredia, plán, test),
# /dev:check --full po poslednom commite (pass.json), bez remote.
exec bash "$(dirname "$0")/../fixtures/scaffold.sh" --feature feature/42-zlava-objednavky \
  --commit "orders-discount=[#42] feat: zľava objednávky s limitom" \
  --commit "orders-discount-test=[#42] test: zľava objednávky pod stropom a nad ním" --checked full
