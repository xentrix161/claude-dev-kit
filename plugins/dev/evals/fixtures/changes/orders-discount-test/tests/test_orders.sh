#!/usr/bin/env bash
. lib/orders.sh

assert_eq 2 "$(orders_count tests/data/orders.csv c100)" "orders_count c100"
assert_eq 0 "$(orders_count tests/data/orders.csv c300)" "orders_count bez objednávok"
assert_eq 900 "$(order_discounted 1000 10)" "order_discounted 10 %"
assert_eq 700 "$(order_discounted 1000 50)" "order_discounted nad stropom 30 %"
