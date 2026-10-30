#!/usr/bin/env bash
# Ceny v centoch (celé čísla), DPH 20 %.

VAT_PERCENT=20

# price_with_vat <cena bez DPH v centoch> — cena s DPH v centoch, zaokrúhlená na najbližší cent
price_with_vat() {
    local net="$1"
    echo $(( net * (100 + VAT_PERCENT) / 100 ))
}

# price_format <centy> — napr. „12,34 €“
price_format() {
    local c="$1"
    printf '%d,%02d €\n' $(( c / 100 )) $(( c % 100 ))
}
