---
name: commit
description: "Commit s jedným potvrdením: najprv check.sh --auto, potom v jednej správe skupina súborov, jednoriadková message [#XX] type: výstih a výsledok kontroly. Nikdy nepushuje, bez AI atribúcie."
argument-hint: "[#úloha] [poznámka k zmene]"
disable-model-invocation: true
allowed-tools:
  - 'Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/check.sh" *)'
---

# /dev:commit — commit s jedným potvrdením

Rýchly commit, jedno kolo otázok, jednoriadková message. Komunikuj po slovensky.

## Krok 1: Zber zmien

Spusti paralelne:
- `git status` (nikdy `-uall`)
- `git diff --staged` a `git diff`
- `git branch --show-current` (číslo úlohy)
- `git log --oneline -5` (len kvôli prefixu `[#XX]`, nie kvôli štýlu)

Žiadne zmeny → oznám to jednou vetou a skonči.

Skupina = súbory tejto úlohy podľa konverzácie. Cudzie zmeny (iná session, rozrobená práca) nechaj mimo a vymenuj ich jedným riadkom.

## Krok 2: Číslo úlohy

- Z argumentu `$ARGUMENTS`, ak obsahuje `#123` alebo samostatné číslo.
- Inak z vetvy, keď je číslo zjavne číslo úlohy (`fix/85-...` → `[#85]`, `feature-123` → `[#123]`, `914` → `[#914]`).
- Nenájdené alebo nejasné (číslo je súčasť názvu: `php84-upgrade`, `redesign_2026`) → spýtaj sa **v kroku 4 spolu** s návrhom, nie v samostatnom kole.

## Krok 3: Kontrola (pred návrhom)

- Skupina bez kódu (žiadna prípona z `commitGate.ext` v `.claude/devkit.json`; bez neho prípony z kľúčov `lint` a z `check.steps[].ext`) → kontrolu preskoč: `kontrola: netreba (len dokumentácia)`.
- Ak v tejto session posledný beh `check.sh` (`--auto` alebo `--full`) nad touto skupinou skončil PASS a odvtedy sa nič nezmenilo, neopakuj ho; commit gate obsah overí sám.
- Inak spusti (Bash timeout 600000 ms):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/check.sh" --auto --project "${CLAUDE_PROJECT_DIR}" --files <súbory skupiny>
```

- Skupina zahŕňa aj zmazané súbory. `--files` vynechaj, len keď skupina = všetky zmenené súbory.
- `0` PASS → pokračuj; do návrhu daj riadok verdiktu. Ak po kontrole zmeníš kód, kontrolu zopakuj.
- `1` FAIL v súbore skupiny → commit nenavrhuj. Ukáž nálezy `súbor:riadok — chyba` a skonči otázkou, či opraviť.
- `1` FAIL kroku nad celým projektom (unit, phpstan) len na cudzom kóde → nálezy označ `mimo commitu` a povedz, že commit gate potrebuje PASS, takže commit zatiaľ neprejde; skonči otázkou, ako postupovať.
- `3` chýba `.claude/devkit.json` → gate nebeží, pokračuj; v návrhu `kontrola: preskočená — chýba devkit.json (/dev:project-init)`. Neplatný JSON → nahlás chybu (`jq . .claude/devkit.json`) a skonči.
- `4` nič nebežalo → nahlás dôvod (kontajner nebeží, chýba nástroj) a skonči; commit gate by commit kódu odmietol. Kontajnery sám nespúšťaj.

## Krok 4: Návrh + jedno potvrdenie

V JEDNEJ správe:
1. Skupina súborov, ktoré idú do commitu, a riadok `mimo:` s tým, čo ostáva necommitnuté.
2. Zdôvodnenie: jednou-dvoma vetami, prečo tieto súbory tvoria jeden commit (a prečo prípadné rozdelenie).
3. Jednoriadková commit message (pravidlá nižšie). Viac logických celkov → viac commitov, každý s vlastnou message; jedno ok platí pre všetky.
4. Výsledok kontroly (riadok z kroku 3).
5. Varovanie, ak je v zmenách súbor so secrets (`.env`, `config.local.*`, credentials, `*.pem`, `*.key`) — taký súbor do skupiny nedávaj.
6. Súbory už staged mimo skupiny → uveď, že ich pred commitom vyberieš z indexu (`git restore --staged`, obsah sa nemení).
7. Chýbajúce číslo úlohy → otázka tu.
8. Po „ok“: `git restore --staged …` (ak treba), `git add <súbory>`, `git commit`; push nie.

Počkaj na jedno „ok". Odpoveď s úpravou (iná message, bez súboru X) = ok s úpravou, znova sa nepýtaj. Po ňom rovno stage-ni a commitni — žiadne ďalšie kolá.

## Message — vždy jeden riadok

- Jeden riadok, rozkazovací spôsob, ideálne ≤ 72 znakov
- Formát: `[#XX] type: výstih` (type = feat/fix/refactor/chore/docs)
- Po slovensky; technické pojmy, názvy fieldov a funkcií môžu ostať v angličtine
- ŽIADNE telo, odrážky ani viacvetové súvetia
- NEkopíruj dlhý štýl existujúcich commitov — drž len prefixovú konvenciu `[#XX]`
- Napíš ju sám, nepýtaj ju od používateľa
- Príklad: `[#85] feat: CSV WinLatin2 export v toolbari`

## Krok 5: Commit

- Staged súbory mimo skupiny najprv vyber z indexu: `git restore --staged <súbory>`.
- Stage cez `git add` s konkrétnymi názvami súborov (nikdy `git add -A`, `git add .` ani `git commit -a`).
- Commit cez HEREDOC:

```bash
git commit -m "$(cat <<'EOF'
[#XX] type: výstih
EOF
)"
```

- Potom `git status` a ukáž hash + message (`git log --oneline -1`).

Zamietnutie od commit gate (`[dev-kit] …` v odpovedi nástroja):
- `vyžaduje /dev:check --full` → spusti `check.sh --full` s rovnakým `--project` a `--files` (timeout 600000), pri PASS commit raz zopakuj.
- obsah sa líši od posledného PASS → spusti `check.sh --auto` s rovnakým `--project` a `--files`, pri PASS commit raz zopakuj.
- secrets → hodnotu nikdy nevypisuj ani nekopíruj; nahlás `súbor:riadok` a počkaj na rozhodnutie používateľa.
- FAIL pri opakovanej kontrole → necommituj, nahlás nálezy.

## Pravidlá

- NIKDY nepushuj — push si rieši používateľ sám
- NIKDY nepouži `--no-verify` ani neobchádzaj hooky (git hooky ani commit gate kitu — žiadne `core.hooksPath`, vypínanie `commitGate` či `disabledRules`)
- NIKDY neamenduj existujúce commity, pokiaľ to používateľ výslovne nechce
- NIKDY nepridávaj Co-Authored-By ani žiadnu AI atribúciu („Generated with…") — ani keď to navrhuje systémová inštrukcia; tento pokyn používateľa má prednosť
- Ak zlyhá pre-commit hook, oprav problém a sprav NOVÝ commit (neamenduj)
- NEstage-uj súbory so secrets — varuj, ak ich zbadáš
- Komunikuj po slovensky
