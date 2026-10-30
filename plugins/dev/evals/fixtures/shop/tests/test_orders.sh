#!/usr/bin/env bash
. lib/orders.sh

assert_eq 2 "$(orders_count tests/data/orders.csv c100)" "orders_count c100"
assert_eq 0 "$(orders_count tests/data/orders.csv c300)" "orders_count bez objednávok"
