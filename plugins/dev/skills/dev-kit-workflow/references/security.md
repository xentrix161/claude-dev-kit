# Bezpečnostné review podľa zmeny

- Pri novom vstupe do aplikácie sleduj požiadavku od vstupu až po čítanie či zmenu dát. Over na serveri rolu, vlastníctvo objektu a oddelenie organizácií. V projektovom harness-e použi syntetické identity pre povolený aj zamietnutý prístup.
- Pri zmene formulára, šablóny, dotazu alebo uploadu over ochranu meniacej požiadavky, escapovanie podľa miesta použitia, parametrizáciu dotazu a oprávnenia k uloženému súboru. Použi ochrany nainštalovanej verzie frameworku.
- Pri zmene toku citlivých údajov over, čo sa dostane do logov, chybových odpovedí, testovacích artefaktov a externých služieb. Použi povolené úložisko a retenčnú dobu projektu. Pri kontrole povoľujúcej len súhrn odovzdaj stav a odkaz na schválený projektový report.
- Pri zmene závislostí over lockfile a spusti projektový audit so schváleným zdrojom. Pri zmene CI, nasadenia alebo oprávnení over účet vykonávajúci zásah, povolený rozsah a požadovaného schvaľovateľa. Zachovaj pravidlá chránených vetiev a prostredí.

K nálezu uveď dotknutú cestu, dopad a dôkaz z kódu alebo povoleného testu. Citlivé hodnoty do reportu nekopíruj.
