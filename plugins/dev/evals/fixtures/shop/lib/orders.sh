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
