---
name: project-init
description: Pripraví lokálny alebo tímový plán nastavenia vrátane kontroly pred commitom.
argument-hint: "[--sync|--dry-run]"
disable-model-invocation: true
---
<!-- vychádza z ECC skills/codebase-onboarding + commands/project-init.md @ b92f181, prestavané -->

# /dev:project-init

Použi inventár spoločného `dev-kit-workflow` a over natívny príkaz v projektových pokynoch, manifeste alebo CI. Uveď jeho zdroj, rozsah a kedy ho projekt vyžaduje. Pri zmiešanom alebo neznámom stacku rozhodujú vstupy konkrétneho modulu.

Režim vyber podľa zadania a argumentov za názvom príkazu. Pre príklady v referenciách je v Codexe `CLAUDE_PLUGIN_ROOT` dva adresáre nad fyzickým adresárom tohto skillu a `CLAUDE_PROJECT_DIR` koreň otvoreného checkoutu.

- **`--sync`** smeruje na [synchronizáciu](references/sync.md). S `--dry-run` ukáž iba diff. V projekte bez inštalácie skonči inventárom.
- **Iba inventár.** Ak používateľ žiada iba zistenie stavu, vypíš pravidlá, harness a rozdiely oproti CI.
- **Bežný init aj `--dry-run`.** Spusti `bash "${CLAUDE_PLUGIN_ROOT}/scripts/init-commit-hook.sh" "${CLAUDE_PROJECT_DIR}"`. Pri existujúcej konfigurácii oznám stav a možnosť synchronizácie. Mimo pracovného stromu Gitu skonči inventárom. Pre nový projekt priprav [plán nastavenia](references/install.md) aj vtedy, keď už má vlastný harness.

V jednom pláne ukáž konkrétne zmeny pre voľbu „iba pre mňa“ alebo „pre tím“ a spôsob kontroly pred commitom. Hook schvaľuje používateľ spolu s plánom. `--dry-run` ukáže ten istý návrh a tým skončí. Pri bežnom inite zapíš schválený variant až po odpovedi. Ak používateľ žiada iba kontrolu pred commitom, zúž plán podľa [pravidiel pre commit](references/commit-hook.md).

Opakovaný onboarding zachová obsah a typ existujúcich súborov vrátane symlinkov. Tímové pokyny patria do `AGENTS.md`.
