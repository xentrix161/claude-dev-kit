# REVIEW.md — pravidlá review projektu

Číta ho `/dev:review` aj zabudovaný `/code-review`. Vlastník: {{vlastník súboru}}. Drž ho krátky; „Nehlásiť" dopĺňaj podľa falošných poplachov.

## Prechody (v tomto poradí)

1. **Bugy** — správnosť: logika, hranice, `null`, chybové stavy, regresia existujúceho správania, oprava chyby bez testu.
2. **Bezpečnosť** — SQL/DQL skladané reťazcom, XSS (vypnuté escapovanie v šablóne), CSRF na formulároch, autorizácia (ACL, votery), tajomstvá v diffe, cesty a súbory od používateľa.
3. **Súlad s plánom** — ak k úlohe existuje `docs/plans/<úloha>-*.md`: diff robí to, čo plán (Súbory, Poradie, Dôkaz), nič z „Mimo rozsahu"; odchýlka bez úpravy plánu v tom istom commite = Important.
4. **Zastaraná dokumentácia** — zmena robí nepravdivým `CLAUDE.md` alebo `.claude/rules/*.md` (príkaz, cesta, názov, pravidlo, ukážka výstupu).

## Important vs. Nit

- **Important** — opraviť pred merge: bug, bezpečnostná diera, strata alebo poškodenie dát, úprava už aplikovanej migrácie, odchýlka od plánu, zavádzajúca dokumentácia.
- **Nit** — môže počkať: čitateľnosť, drobné zjednodušenie, nepresný komentár, zastaraný údaj v docs bez dopadu.
- **Max 5 nitov** — len najhodnotnejšie, zvyšok vynechaj.
- Hlás len pri istote > 80 % po overení v kóde; podobné nálezy zlúč; bezpečnosť prvá.
- Formát: `🔴 N. súbor:riadok — výstih`; Important = 🔴 CRITICAL alebo 🟡 WARNING, Nit = 🔵 SUGGESTION.

## Nehlásiť

- vendor a generovaný kód: `vendor/`, `node_modules/`, {{ďalšie vendor alebo generované cesty}}
- čo stráži nástroj v `/dev:check`: štýl ({{nástroj na štýl}}), typy a statická analýza ({{nástroj na analýzu}}), chyby už zapísané v baseline
- zámerné rozhodnutia projektu: {{zámerné rozhodnutia, napr. názvy ponechané kvôli spätnej kompatibilite}}
- legacy kód mimo zmenených riadkov, ak zmena jeho správanie nemení
- osobné preferencie bez dopadu (pomenovanie, poradie importov, formátovanie)

## Projektové kontroly

- {{kontrola špecifická pre projekt, napr. povinné atribúty v šablónach alebo JS kotvy}}

## Pasce

- {{miesto, kde review v minulosti prehliadlo chybu, a na čo sa pozrieť}}
