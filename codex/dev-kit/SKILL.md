---
name: dev-kit
description: Ručné príkazy dev-kitu pre otvorený projekt. Prvé slovo vyberá postup.
---

# Príkazy dev-kitu

Prvé slovo za `$dev-kit` je názov príkazu, napríklad `init`, `check`, `review` alebo `mr`. Zvyšok správy sú argumenty a zadanie. Pri prázdnom vstupe alebo otázke na dostupné príkazy vypíš ponuku cez `bash scripts/command.sh --list` z adresára tohto skillu.

Načítaj návod cez `bash scripts/command.sh <názov>` z adresára skillu. Skriptu odovzdaj iba názov. Pri neznámom názve ukáž ponuku. Relatívne odkazy v návode patria k vypísanej ceste `SKILL.md`. Samotnú úlohu vykonaj v pôvodnom pracovnom adresári používateľa podľa jeho zadania, projektových pokynov a natívneho harnessu.

V návode `$ARGUMENTS` označuje zvyšok správy. Za `CLAUDE_PLUGIN_ROOT` dosaď vypísaný adresár pluginu a za `CLAUDE_PROJECT_DIR` koreň aktuálneho projektového checkoutu. Pri vnorenom `/dev:<príkaz>` načítaj príslušný postup rovnakým spôsobom. Povinný projektový príkaz vykonaj aj bez `.claude/devkit.json`.

Úvodné čítacie príkazy označené výkričníkom vykonaj podľa potreby raz v projekte. Dodrž obmedzenia na čítanie pri `explain`, `mr` a `stats`. Zápis, commit, publikovanie, prehliadač aj delegovanie podliehajú pravidlám aktuálnej relácie. Pri commite over všetky povinné kontroly a presný index. Výsledky hookov, zámkov či iných nástrojov uvádzaj iba podľa skutočne dostupných dôkazov. Štatistika sumarizuje zaznamenané udalosti kitu. Odovzdávku v ďalšom chate načítaj z dohodnutého dokumentu.
