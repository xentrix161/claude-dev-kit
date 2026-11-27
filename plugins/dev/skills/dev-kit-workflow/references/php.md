# PHP pred commitom

Použi príkazy projektu v jeho PHP runtime. Najprv prečítaj, čo jeho pre-commit alebo CI skript skutočne spúšťa. Zaznamenaj pokryté kroky raz. Pri rozdiele medzi lokálnym harnessom a CI porovnaj rozsah, argumenty, konfiguráciu a verziu PHP.

| Kedy | Čo overiť |
|---|---|
| Pred commitom v PHP aplikácii s Composerom | Audit zamknutých závislostí podľa projektu (napr. `composer audit --locked`, vrátane vývojových balíkov podľa pravidiel projektu). Použi schválený zdroj advisories. Nedostupný zdroj znamená neúplné overenie. |
| Pred commitom v projekte s PHPStan | Spusti konfiguráciu, level a rozsah určené projektom. Ak má analyzovať celý projekt, platí to aj pri oprave jedného súboru. |
| Zmena logiky alebo správania | Vyber unit testy dotknutého správania a jeho volajúcich vrátane relevantného chybového prípadu. |
| Zmena DB, DI, oprávnení, API alebo externej služby | Spusti príslušné integračné scenáre cez skutočný vstup. Pri Nette over vytvorenie presentera alebo služby cez projektový kontajner a vykreslenie dotknutej Latte. Pri Symfony over dotknutú routu alebo konzolový príkaz cez kernel. |
| Zmena používateľského toku alebo toku medzi systémami | Spusti príslušný E2E scenár so syntetickými dátami a over konečný účinok. Ak sa menil aj frontend, použi [JS a UI](js.md). |

Širší rozsah požadovaný projektom má prednosť. Ak projekt výslovne určuje inú politiku, uveď ju. Ak vhodná sada chýba, povedz, čo si overil a čo zostáva nepokryté. Povinný neúspešný, zablokovaný alebo nespustený krok zastaví commit. Pri zmene platformy či rozšírení over aj `composer check-platform-reqs` v cieľovom runtime.
