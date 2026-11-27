---
name: dev-kit-workflow
description: Vývoj od drobnej opravy po review a MR podľa pravidiel projektu. Aj na zavedenie alebo výklad AI-native SDLC.
---

# Práca na projekte

Projekt určuje runtime, dáta, oprávnenia, rozsah a povinné kontroly aj bez konfigurácie kitu. Pri prvom zásahu v module a pred commitom over príslušné pokyny a vstup do harnessu. Pri onboardingu alebo nejasnosti pomôže `bash scripts/project-context.sh <adresár>` z adresára skillu. Skrátené či tienené pokyny dočítaj z disku. V Codexe rešpektuj bližšie pokyny a `AGENTS.override.md`, v Claude over načítanie tímových pravidiel aj pri vlastnom `CLAUDE.md`.

**Drobná oprava s jasným dosahom.** Stačí zadanie, dotknuté miesto a cielené overenie. Pri preklepe skontroluj výsledný text v jeho kontexte. Pri chybe v logike reprodukuj pôvodný prípad a over opravu na skutočnom volajúcom. Zachovaj rozpracovanú prácu a použi existujúce komponenty. Stručne uveď výsledok a čo ešte čaká. Samostatný plán, celú testovaciu sadu či odovzdávací dokument pridaj len na základe zadania, dopadu alebo pravidiel projektu.

**Rozsah zväčši podľa následkov.** Aj jednoriadková zmena oprávnenia potrebuje povolený a zamietnutý prípad. Pri zmene spoločného kontraktu over dotknutých volajúcich. Pre väčšiu zmenu, review, MR alebo výklad použi príslušnú časť [playbooku](references/playbook.md).

Povinné projektové kontroly spusti v predpísanej fáze aj pri malej zmene. Chýbajúci alebo neúspešný povinný výsledok blokuje commit. Rovnaký beh započítaj raz podľa pravidiel projektu pre obsah, staging a rozsah. Pred PHP commitom otvor [PHP](references/php.md), pri zmene JS alebo interakcie [JS a UI](references/js.md), pri zmene prístupu alebo spracovania citlivých dát [bezpečnosť](references/security.md), pri produkčnom audite, migrácii, dávkovej prevádzke, nasadení či incidente [prevádzku](references/operations.md).
