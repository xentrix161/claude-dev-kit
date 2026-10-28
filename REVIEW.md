<!-- dev-kit: common/REVIEW.md @ 0.1.1 -->
# REVIEW.md — pravidlá review projektu

Číta ho `/dev:review` aj zabudovaný `/code-review`. Vlastník: správca dev-kit. Drž ho krátky; „Nehlásiť" dopĺňaj podľa falošných poplachov.

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

- vendor a generovaný kód: `vendor/`, `node_modules/`, `plugins/dev/LICENSES/`
- čo stráži nástroj v `/dev:check`: štýl (`bash -n`, `jq empty`), typy a statická analýza (`tests/selftest.sh`, `claude plugin validate --strict`, `guard:bash4`, `guard:gnu-only`), chyby už zapísané v baseline
- zámerné rozhodnutia projektu: dlhé ERE regexy v `lib.sh` a `pre-bash.sh` (BSD aj GNU grep bez `\s` v zátvorkách), kusy ECC zámerne prepísané po slovensky a stručne, príkazové skilly s `disable-model-invocation: true`
- legacy kód mimo zmenených riadkov, ak zmena jeho správanie nemení
- osobné preferencie bez dopadu (pomenovanie, poradie importov, formátovanie)

## Projektové kontroly

- Zmena správania skriptu alebo hooku bez úpravy `docs/SPEC.md` alebo bez prípadu v `tests/selftest.sh` = Important.
- Hook, ktorý môže blokovať projekt bez `.claude/devkit.json`, pri nebežiacom kontajneri alebo chýbajúcom nástroji = Important.
- Meno človeka, klienta či projektu alebo osobná cesta v obsahu repa = Important (repo je verejné).
- Hláška pre ľudí nie po slovensky alebo bez diakritiky = Nit.

## Pasce

- Dlhší popis skillu alebo agenta zväčší always-on kontext každej session — over `make details` (≤ 3000 tokenov).
