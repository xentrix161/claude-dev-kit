---
name: plan
description: "Zapíše dohodnutý plán úlohy do docs/plans/<úloha>-<slug>.md (úloha, súbory, poradie, riziká, dôkaz, mimo rozsahu). Pri malej úlohe povie, že plán netreba."
argument-hint: "[názov alebo opis úlohy]"
disable-model-invocation: true
---

# /dev:plan — plán ako artefakt v repe

Plán ide do repa spolu so zmenou; `/dev:review` podľa neho kontroluje diff. Komunikuj po slovensky.

## 1. Treba plán?

- Netreba, keď úloha mení ≤ 3 súbory a nezasahuje rizikové cesty → povedz jednou vetou `plán netreba (≤ 3 súbory, bez rizikových ciest)` a skonči. Ak používateľ trvá na pláne, zapíš ho.
- Rizikové cesty: `check.fullWhen`, `migrations.paths` a `pairs[].when` z `.claude/devkit.json`; bez neho DB migrácie a schéma, validácia vstupov, autentifikácia a oprávnenia, verejné API, DB triggery, konfigurácia nasadenia.

## 2. Zdroj

- Dohodnutý plán z tejto konverzácie (plan mode, odsúhlasený návrh) + argument `$ARGUMENTS`.
- Nič dohodnuté nie je → zostav návrh z argumentu a čítania kódu, ukáž ho celý (Súbory, Poradie, Riziká, Dôkaz) a počkaj na jedno ok. Až potom zapisuj.
- Nevymýšľaj: čo nie je overené v kóde, daj do Rizík s `?`.

## 3. Súbor

- Číslo úlohy: z argumentu (`#123`), inak z vetvy (`git branch --show-current`), keď je zjavne číslo úlohy (`fix/85-…`, `914`); nejasné (`php84-upgrade`) alebo žiadne → dátum `YYYY-MM-DD` a nadpis bez `[#…]`.
- Slug: 2–5 slov, malé písmená, bez diakritiky, spojené pomlčkou.
- Cesta: `docs/plans/<úloha>-<slug>.md`, napr. `docs/plans/85-csv-export.md`. Chýbajúci adresár vytvor.
- Súbor už existuje → uprav ho, neprepisuj naslepo; ukáž, čo sa mení.

## 4. Obsah (≤ 60 riadkov, len odrážky)

- Projekt má v `docs/plans/` vlastnú formu → drž ju.
- Inak prečítaj šablónu `${CLAUDE_PLUGIN_ROOT}/templates/common/plan.md`, vyplň `{{…}}` a vynechaj jej prvý riadok s komentárom.
- Šablóna chýba → sekcie: Úloha (+ vetva, dátum, stav, zdroj) · Súbory · Poradie · Riziká · Dôkaz · Mimo rozsahu · Odchýlky.
- Súbory a poradie sedia s tým, čo sa naozaj bude meniť — žiadne „prípadne".
- Dôkaz = spustiteľné príkazy s výstupom, ktorý znamená úspech (`/dev:check --full` PASS, konkrétny test `súbor::metóda`, ručný krok v appke len ak treba).
- Mimo rozsahu = čo sa vedome nerobí; kandidáti na follow-up.

## 5. Po zapísaní

- Necommituj. Lokálny režim (`git check-ignore -q docs/plans/x.md` uspeje): plán ostáva len na disku a do commitu nejde. Tímový režim: plán ide s prvou zmenou cez `/dev:commit`.
- Platí do konca úlohy: keď sa implementácia od plánu odchýli (iné súbory, poradie, vypustený krok), uprav plán a pridaj riadok do `## Odchýlky` (v tímovom režime v tom istom commite ako zmenu kódu).
- Po dokončení prepni `Stav` na `hotový`.

## 6. Výstup

- `docs/plans/…md` — vytvorený / upravený
- zoznam súborov s tým, čo sa v nich mení, kroky v poradí, hlavné riziko jednou vetou a príkaz dôkazu
- otázka len vtedy, keď bez odpovede nejde pokračovať
