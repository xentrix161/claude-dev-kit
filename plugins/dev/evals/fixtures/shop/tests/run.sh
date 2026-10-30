#!/usr/bin/env bash
# Spustí tests/test_*.sh, alebo len zadané súbory. Exit 1, keď niektorý test zlyhá.
cd "$(dirname "$0")/.." || exit 2
[ $# -gt 0 ] || set -- tests/test_*.sh
rc=0
for t in "$@"; do
    echo "# $t"
    bash -c '. tests/assert.sh; . "$1"; [ "$FAILS" = 0 ]' _ "$t" || rc=1
done
if [ "$rc" = 0 ]; then echo "PASS"; else echo "FAIL"; fi
exit "$rc"
