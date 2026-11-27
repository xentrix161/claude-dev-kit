# Migrácie, dávky a nasadenie

- Pri zmene importu, fronty alebo dávky over na syntetickej vzorke opakované doručenie a pokračovanie po prerušení. Skontroluj počet aj obsah výsledkov a vedľajších účinkov.
- Pri migrácii over kompatibilitu počas prechodu medzi verziami aplikácie. Pri riziku straty dát dolož spôsob návratu a posledné skutočné overenie obnovy do izolovaného prostredia. Ak je k dispozícii iba plán, uveď to.
- Pri zmene pipeline sleduj poradie až po nasadzovaný artefakt. Urči, ktoré kontroly môžu zastaviť nasadenie tejto verzie a ktoré bežia až potom. Pri vydaní dohodni signál úspechu, prah na návrat a vlastníka rozhodnutia. Vyber len údaje potrebné pre danú zmenu, bez osobných údajov v reporte.

Pri audite prístupu, citlivých dát alebo oprávnení na nasadenie použi [bezpečnostné pravidlá](security.md). Pri produkčnom audite over všetky povinné release kontroly projektu pre danú revíziu a rozsah aj bez konfigurácie kitu. Spusti bezpečný natívny príkaz alebo dolož platný projektový report. Ak povinný harness zlyhá, neprebehne alebo nedoloží rozsah, výsledok je **Blokované**. Doplnkový PASS uveď zvlášť. Nasadenie vyžaduje osobitné poverenie.

## Monitoring a incidenty

- Pri dohodnutom monitoringu použi existujúcu kontrolu projektu. Zmeraj bežnú hodnotu signálu, zvoľ prah podľa dopadu a urč, čo bude znamenať obnovenie služby. Opakované hlásenia jedného incidentu zlúč a nastav odstup medzi upozorneniami. Dohodnuté opakované kontroly nastav v plánovači projektu alebo hostiteľa. Oznám významnú zmenu stavu.
- Začni čítaním metrík, logov a výsledkov CI v povolenom prostredí. Zaznamenaj čas, verziu, pozorovaný dopad, pravdepodobnú príčinu a čo ešte treba potvrdiť.
- Pred opakovaním zásahu urč časový alebo početný limit, povolené akcie a podmienku eskalácie. Produkčný zásah, návrat verzie, vyradenie testu aj opakovaná úloha vyžadujú zodpovedajúce poverenie. Pred ďalším pokusom posúď novú evidenciu. Pri vyčerpaní limitu odovzdaj stav vlastníkovi.
- Po zásahu znovu over pôvodný používateľský tok alebo metriku. Výsledok a zostávajúcu neistotu pripoj k incidentu, príčinu pokry regresiou alebo opravou prevádzkového postupu. Ohraničenú opravu veď cez bežné kontroly a review. Väčší zásah zaznamenaj ako samostatné zadanie.
