#!/usr/bin/env bash
. lib/price.sh

assert_eq 1200 "$(price_with_vat 1000)" "price_with_vat 1000"
assert_eq 300 "$(price_with_vat 250)" "price_with_vat 250"
assert_eq "12,34 €" "$(price_format 1234)" "price_format 1234"
