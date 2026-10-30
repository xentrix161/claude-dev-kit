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

# orders_export <súbor> <zákazník> <cieľový súbor> — objednávky zákazníka do samostatného CSV
orders_export() {
    local file="$1" customer="$2" out="$3"
    eval "grep '^[0-9]*;$customer;' $file" > "$out"
}

# orders_sum <súbor> — súčet všetkých objednávok v centoch
orders_sum() {
    local file="$1" n i=1 total=0 line
    n=$(wc -l < "$file")
    while [ "$i" -lt "$n" ]; do
        line=$(sed -n "${i}p" "$file")
        total=$(( total + ${line##*;} ))
        i=$(( i + 1 ))
    done
    echo "$total"
}
