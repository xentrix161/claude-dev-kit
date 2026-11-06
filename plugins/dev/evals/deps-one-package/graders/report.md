---
type: llm
---

PASS, ak odpoveď uvádza `acme/slugify` 3.1.0 → 3.2.0, zhŕňa changelog verzie 3.2.0 (nový parameter `$separator`, zastarané `Slugify::create()`) a menuje jeho použitie v `src/ProductSlug.php` ako vec na neskôr, uvádza výsledok kontroly (PASS) a vytvorený commit (hash a správu).
FAIL, ak aktualizoval aj `acme/money` alebo všetky balíky, ak si vymyslí zmenu, ktorú changelog neuvádza, ak tvrdí, že zmeny pushol, alebo ak commit nevznikol.
