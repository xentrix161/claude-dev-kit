# Čo sa v dev-kite zmenilo od verzie 0.5.1 a prečo

Vydanie 0.5.1 už malo pre Claude Code príkazy, projektové šablóny, hooky aj kontrolu pred commitom. Pripravovaná zmena sprístupňuje tie isté pracovné postupy v Codexe. V oboch klientoch určuje pravidlá otvorený projekt. Jeho harness je skript, Make cieľ alebo iný vstup, ktorým tím overuje zmenu lokálne či v CI.

## Jeden pracovný postup pre oba nástroje

Codex cez `@dev-kit` vyberie rovnaký návod, aký používa príslušný príkaz `/dev:*` v Claude. Pri zmene postupu stačí upraviť jeden zdroj. Spoločné tímové pokyny patria do `AGENTS.md`. Pri onboardingu sa zohľadňujú aj vnorené pravidlá, existujúce pokyny Claude a symlinky. To umožňuje použiť kit aj v projekte s vlastným nastavením alebo bez šablóny pre jeho jazyk. [Použitie v oboch klientoch](../README.md)

Spoločný playbook rozvíja fázy AI-native SDLC od zadania po prevádzku. Pri oprave preklepu stačí overiť výsledný text v jeho kontexte. Pri zmene oprávnenia treba vyskúšať povolený aj zamietnutý prípad. Väčší návrh dostane kritériá úspechu, dotknuté rozhrania, riziká a spôsob obnovy podľa dopadu. Povinné projektové kontroly platia aj pri malej zmene. [Playbook a jeho pôvod](../plugins/dev/skills/dev-kit-workflow/references/playbook.md) · [Pôvod adaptovaných častí kitu](../plugins/dev/PROVENANCE.md)

## Init a náklady na kontext

Init najprv vyhľadá pravidlá, skutočné príkazy projektu a aktívny Git hook. V jednom návrhu ukáže kontrolu pred commitom aj rozdiel medzi nastavením „iba pre mňa“ a „pre tím“. Používateľ schvaľuje konkrétny diff. Pri tímovom variante init preverí, že Git vidí každý zdieľaný súbor, aj keď projekt pôvodne ignoroval celý adresár nastavení. Súkromné súbory si zachovajú svoje vylúčenie. Existujúca inštalácia ponúkne synchronizáciu a `--dry-run` umožní pozrieť si návrh pred zápisom. [Postup initu](../plugins/dev/skills/project-init/SKILL.md)

Pôvodný init načítal aj pokyny na inštaláciu, synchronizáciu a vypĺňanie všetkých šablón. Teraz si otvorí len referencie potrebné pre vybranú vetvu postupu. Pri porovnaní tagu `dev--v0.5.1` a tejto úpravy tým istým Claude Code 2.1.314 klesol odhad pri otvorení `project-init` z **10 900 na 410 tokenov**. Ďalšie čítanie závisí od úlohy. `make details` stráži limit 1 500 tokenov pri otvorení initu a 3 000 pre trvalý kontext pluginu. [Spôsob merania](DEVELOPMENT.md#rozpočet-kontextu)

## Kto vykoná kontrolu pred commitom

Claude ju pripája cez plugin. Codex má osobný hook pre shellový commit, ktorý si používateľ zaregistruje a potvrdí mu dôveru. Inštalátor zachová existujúce registrácie, zálohuje menený súbor a upozorní na duplicitu. Tímová konfigurácia určuje povinný skript. O tom, kto ho vykoná, rozhoduje stav konkrétneho klonu.

| Situácia | Správanie a dôvod |
|---|---|
| Git má aktívny dohodnutý verzovaný hook | Ak nezmenený skript pokrýva jediný povinný krok a pripravený obsah zodpovedá pracovnému stromu, kit prenechá kontrolu Gitu. Testy tak prebehnú raz. |
| Kolega si projekt čerstvo naklonoval | Ak Git hook v jeho klone ešte nie je aktívny, zapnutý kit vyžaduje úspešný výsledok toho istého skriptu. Kolega dostane rovnakú kontrolu aj s iným lokálnym nastavením Gitu. |
| Git hook pokrýva len časť požiadaviek | Kit vyžaduje aj ostatné povinné kroky. Ak Git pri commite zopakuje časť kontroly, init na to upozorní. |
| Vývojár commituje ručne z terminálu alebo IDE | Automatickú kontrolu pred takým commitom zabezpečuje aktívny Git hook projektu. Osobný hook asistenta pôsobí pri jeho shellovom príkaze. |

Podmienky odovzdania kontroly Gitu aj príklad konfigurácie sú v [referencii nastavení](devkit-json.md).

## Ktorému výsledku možno veriť

- **Staging.** Povinný krok používa celý projektový príkaz vrátane jeho argumentov a prostredia. Výsledok sa viaže na revíziu, konfiguráciu a overený obsah. Pri následnej zmene pripravených súborov treba nové overenie. Pravidlo zahŕňa zmenu typu súboru, prázdny commit aj úpravu správy. Ak projekt kontroluje pred `git add`, pri nových cestách musí výsledný report ukázať ich zahrnutie alebo projektom odôvodnené vylúčenie.
- **Súbeh kontrol.** Každý beh vráti svoj výsledok. Pre commit a MR kit sleduje posledný začatý beh. Starší úspech, ktorý dobehne neskôr, preto neprekryje novšie zlyhanie. Režim `full` vykoná aj povinné kroky z `quick`.
- **Popis MR.** Kit overí, ku ktorému commitu úspešný beh patrí. Rozsah kontrolovaného diffu musí doložiť projektový report alebo CI. Ak harness pri relevantnej zmene vybral nula súborov, v sekcii „Ako overiť“ zostane skutočný počet a výslovné „Pokrytie MR: neoverené“. Recenzent tak vidí, čo ešte treba overiť. [Pravidlá pre popis MR](../plugins/dev/skills/mr/SKILL.md)

## Odborné pravidlá načítané podľa úlohy

| Oblasť | Čo a prečo sa mení |
|---|---|
| PHP, Nette a Symfony | Šablóny preberajú audit zamknutých závislostí zo schváleného zdroja, celý príkaz PHPStan a projektové testovacie sady vrátane wrapperov a predpokladov Make cieľa. Tým sa zachová úroveň analýzy aj prostredie projektu. Unit, integračný alebo E2E test sa vyberá podľa zmeneného správania. Rýchla kontrola na konci ťahu má vlastný rozsah. [PHP](../plugins/dev/skills/dev-kit-workflow/references/php.md) |
| JavaScript a UI | Výber buildu, typovej kontroly a testov vychádza z modulu a CI. Pri zmene prepojenia šablóny s JavaScriptom sa overí skutočná interakcia a jej výsledok. Tak sa zachytí aj chyba medzi dvoma samostatne funkčnými časťami. [JS a UI](../plugins/dev/skills/dev-kit-workflow/references/js.md) |
| Bezpečnosť | Podľa zmeny sa overuje vlastníctvo objektu, oprávnenie, ochrana vstupov a tok citlivých údajov. Citlivý krok môže ukladať stav a metadáta bez štandardného a chybového výstupu. Šablóny pre worktree vynechávajú súkromné nastavenia a prihlasovacie súbory. [Bezpečnosť](../plugins/dev/skills/dev-kit-workflow/references/security.md) |
| Prevádzka | Pri migrácii alebo dávke sa preverí obnova a bezpečné opakovanie. Pri nasadení a incidente sa určia signál úspechu, hranice zásahu a vlastník rozhodnutia. Produkčný audit vyžaduje projektové kontroly pre príslušnú revíziu a rozsah aj bez konfigurácie kitu. [Prevádzka](../plugins/dev/skills/dev-kit-workflow/references/operations.md) |

## Ako sa zmena overila

Pri príprave úpravy prešlo 216 regresných prípadov. Skúšky v skutočných klientoch Codex a Claude použili dočasné Git repozitáre so syntetickým projektovým skriptom. Overili zastavenie commitu bez platného výsledku aj úspešný commit s jediným vykonaním skriptu. Samostatné regresie pokrývajú rozdielne nastavenie dvoch klonov, zmenu stagingu, súbeh kontrol a ignorované tímové súbory. Scenár evalu pre text MR zahŕňa aj nulový výber. Platený eval zostáva samostatným krokom pred vydaním. [Kontroly kitu a eval suite](DEVELOPMENT.md)
