#!/usr/bin/env bash
. lib/cart.sh

assert_eq 750 "$(cart_line_total 3 250)" "cart_line_total 3 250"
assert_eq 650 "$(cart_total tests/data/cart.csv)" "cart_total dvoch riadkov"
assert_eq 3 "$(cart_item_count tests/data/cart.csv)" "cart_item_count dvoch riadkov"
