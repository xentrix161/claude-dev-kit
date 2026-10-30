#!/usr/bin/env bash
# assert_eq <očakávané> <skutočné> <popis> — riadok „ok - …“ alebo „not ok - …“, zlyhania v FAILS.
FAILS=0

assert_eq() {
    if [ "$1" = "$2" ]; then
        echo "ok - $3"
    else
        echo "not ok - $3: čakal som '$1', dostal som '$2'"
        FAILS=$(( FAILS + 1 ))
    fi
}
