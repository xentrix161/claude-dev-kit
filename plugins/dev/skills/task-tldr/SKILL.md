---
name: task-tldr
description: Krátke, ľudské a netechnické zhrnutie zapracovaného tasku v bodoch a pododrážkach — na vloženie do tasku/tiketu pre zadávateľa, PM alebo metodika. Použi vždy, keď používateľ po práci chce TLDR do tasku, zhrnutie „ľudsky", „čo napíšem do tasku", „zhrň čo sme spravili", „daj mi to do tasku", „zhrnutie pre zadávateľa" alebo prepísať technické zhrnutie zrozumiteľne — aj keď skill výslovne nespomenie.
---

# Task TLDR

Zhrnutie hotovej práce pre človeka, ktorý nečíta kód (zadávateľ, PM, metodik). Používateľ si výsledok skopíruje do tasku, takže musí byť zrozumiteľný sám o sebe a čitateľný za pár sekúnd. Technické detaily sú v commite a v kóde — sem nepatria. Komunikuj po slovensky.

## Step 1: Zisti, čo sa spravilo

- Primárne z konverzácie: čo sa zapracovalo, čo sa rozhodlo a či treba po nasadení niečo spraviť ručne.
- Ak kontext chýba (nová session, používateľ len povie „daj TLDR do tasku"), zisti to z gitu — bez checkoutu:
  - `git branch --show-current`
  - `git log --oneline master..HEAD` (alebo `main`, podľa repa; pri inej vetve `master..<vetva>`)
  - `git diff --stat master...HEAD` a pri nejasnostiach samotné zmeny
- Z kódu odvoď dopad pre používateľa systému (čo sa zmení na webe, v administrácii, v API), nie zoznam zmenených súborov.

## Step 2: Napíš zhrnutie

Tvar:
- 2–4 hlavné body = veci, ktoré sa zmenili, **tučným** (napr. „**Nové stavy objednávky Čaká na platbu a Pripravená na odber**")
- pod každým 1–3 krátke odrážky
- heslá, nie celé vety
- jedna odrážka = jedna vec, ideálne do 10 slov — čitateľ text len preletí očami. Ak sa ponúka bodkočiarka alebo „a zároveň", rozdeľ to na dve odrážky alebo menej dôležitú vec vynechaj
- spolu najviac 8 pododrážok. Pri veľkom rozsahu vyber to, čo zadávateľa zaujíma, a drobnosti (vzhľad tlačidiel, stránkovanie…) zlúč do jednej odrážky alebo vynechaj — kratšie zhrnutie prečíta celé, dlhý zoznam nie
- posledný bod **Po nasadení** len vtedy, keď treba niečo spraviť ručne (prepnúť v administrácii, nahrať údaje) — tiež ľudsky
- výstup sú len odrážky: bez nadpisu, úvodu, záveru a bez bloku kódu, aby sa dal rovno skopírovať

Ak používateľ chce iný tvar (dlhší, pre vývojára, iný jazyk), prispôsob sa — toto je predvolený tvar pre task.

## Čo do zhrnutia nepatrí

Čitateľ tasku tieto veci nepotrebuje a len by ho zdržali:
- názvy súborov, tried, tabuliek, polí, routes, URL, príkazy, commity, vetvy
- počty záznamov, merania, výsledky testov
- interné identifikátory (`order_status`, `export_filter`) — preveď ich na názov, ktorý používateľ systému pozná („stav objednávky", „export pre porovnávače cien")
- ako sa k riešeniu prišlo, slepé uličky a zvažované alternatívy

Pojmy, ktoré používateľ systému a tím poznajú, sú v poriadku: číselník, administrácia, API, API dokumentácia, verejné/neverejné, import, export, aj názvy externých systémov, zdrojov a štandardov, ktoré zadávateľ pozná.

## Príklad

Situácia: e-shop dostal dva nové stavy objednávky, zrušené produkty sa prestali posielať do exportu pre porovnávače cien a po nasadení treba v administrácii doplniť text e-mailu pre nový stav.

Dobrý výstup:

- **Nové stavy objednávky Čaká na platbu a Pripravená na odber**
  - vidno ich v administrácii aj v zákazníckom účte
  - zákazník dostane e-mail pri zmene stavu
  - staré objednávky bez zmeny
- **Export produktov pre porovnávače cien**
  - zrušené produkty sa už neposielajú
  - vypredané produkty ostávajú s dostupnosťou „na objednávku"
- **Po nasadení**
  - v administrácii doplniť text e-mailu pre stav Pripravená na odber

Zlý výstup (príliš technický a dlhý) — takto nie:

- **Migrácia** `Version20261015100000`: tabuľky, dáta, `order_status`, `export_filter`, changelog …
- **Po nasadení:** `php bin/console app:cache:http purge order_status` …
