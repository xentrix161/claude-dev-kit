# CLAUDE.md — shop

Malá knižnica e-shopu v bashi (košík, ceny s DPH, objednávky) a trieda `src/ProductSlug.php` nad balíkmi z Composeru.

## Príkazy

| Úloha | Príkaz | Zdravý výstup |
|---|---|---|
| testy | `bash tests/run.sh` | `ok - …` pri každom teste |
| composer | `bin/composer <príkaz>` (wrapper projektu, nie globálny `composer`) | výstup Composeru |
| kontrola zmien | `/dev:check` | `[dev-kit] check quick: PASS` |

## Pravidlá

1. Sumy sú celé čísla v centoch, nikdy desatinné.
2. Novú závislosť (`composer require`) len so súhlasom; `composer.json` a `composer.lock` commitni spolu.
3. Commit: `[#123] typ: výstih` po slovensky; `git push` len na výslovný pokyn.
