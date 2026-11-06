#!/usr/bin/env bash
# Objednávky: riadky „<id>;<zákazník>;<suma v centoch>“.

# orders_count <súbor> <zákazník> — počet objednávok zákazníka
orders_count() {
    local file="$1" customer="$2" n=0 id who sum
    while IFS=';' read -r id who sum; do
        [ "$who" = "$customer" ] && n=$(( n + 1 ))
    done < "$file"
    echo "$n"
}

# order_discounted <suma v centoch> <zľava v %> — suma po zľave; zľava nad SHOP_MAX_DISCOUNT_PERCENT sa oreže
order_discounted() {
    local sum="$1" pct="$2" max="${SHOP_MAX_DISCOUNT_PERCENT:-30}"
    [ "$pct" -le "$max" ] 2>/dev/null || pct=$max
    echo $(( sum - sum * pct / 100 ))
}
