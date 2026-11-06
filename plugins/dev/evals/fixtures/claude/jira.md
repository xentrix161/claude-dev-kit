# CLAUDE.md — shop

Malá knižnica e-shopu v bashi: košík, ceny s DPH, objednávky. Úlohy sa evidujú v Jire (projekt `ABC`).

## Príkazy

| Úloha | Príkaz | Zdravý výstup |
|---|---|---|
| testy | `bash tests/run.sh` | `ok - …` pri každom teste |
| kontrola zmien | `/dev:check` | `[dev-kit] check quick: PASS` |

## Pravidlá

1. Sumy sú celé čísla v centoch, nikdy desatinné.
2. Nová funkcia v `lib/` → test v `tests/`.
3. Commit: `ABC-123 výstih` — kľúč úlohy z Jiry na začiatku, bez typu, po slovensky; `git push` len na výslovný pokyn.
