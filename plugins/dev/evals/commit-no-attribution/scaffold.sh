#!/usr/bin/env bash
# Pracovný priestor prípadu (claude plugin eval --scaffold): projekt ../fixtures/shop ako git repo.
exec bash "$(dirname "$0")/../fixtures/scaffold.sh" --branch feature/12-pocet-poloziek --change cart-count
