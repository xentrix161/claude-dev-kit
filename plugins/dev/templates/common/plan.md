<!-- /dev:plan: len pre úlohy nad 3 súbory alebo s rizikovými cestami; pri odchýlke uprav plán v tom istom commite ako kód -->
# [#{{úloha}}] {{názov}}

- Vetva: `{{vetva}}` · Dátum: {{dátum}} · Stav: návrh / schválený / hotový
- Zdroj: {{tiket, príloha alebo rozhodnutie — odkaz alebo cesta}}

## Úloha

- {{čo má platiť po zmene — merateľne, 1–3 odrážky}}

## Súbory

- `{{cesta}}` — {{čo sa mení}}

## Poradie

1. {{krok — po každom kroku prejde `/dev:check`}}

## Riziká

- {{riziko}} — {{ako ho zmierniť alebo čo overiť}}

## Dôkaz

- `/dev:check --full` PASS
- {{test, ktorý pred zmenou padá a po nej prechádza: `súbor::metóda`}}
- {{ručné overenie: URL alebo príkaz a očakávaný výstup}}

## Mimo rozsahu

- {{čo sa vedome nerieši — kandidát na follow-up}}

## Odchýlky

- {{dátum}} — {{čo sa zmenilo oproti plánu a prečo}}
