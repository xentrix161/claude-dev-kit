#!/usr/bin/env bash
# Košík: riadky „<sku>;<počet>;<cena za kus v centoch>“.

# cart_line_total <počet> <cena za kus> — cena riadku v centoch
cart_line_total() {
    echo $(( $1 * $2 ))
}

# cart_total <súbor košíka> — súčet riadkov v centoch bez DPH
cart_total() {
    local file="$1" sku qty unit total=0
    while IFS=';' read -r sku qty unit; do
        [ -n "$sku" ] || continue
        total=$(( total + qty * unit ))
    done < "$file"
    echo "$total"
}

# cart_item_count <súbor košíka> — počet kusov vo všetkých riadkoch
cart_item_count() {
    local file="$1" sku qty unit n=0
    while IFS=';' read -r sku qty unit; do
        [ -n "$sku" ] || continue
        n=$(( n + qty ))
    done < "$file"
    echo "$n"
}
