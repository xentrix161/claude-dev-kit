# Ako kit používa AI-native SDLC

| Fáza | Čo prináša kit | Čo dodáva projekt |
|---|---|---|
| Zámer | Otázka, kto potrebuje zmenu a aký výsledok očakáva | Zadanie, rozhodnutie vlastníka, hranice rozsahu |
| Návrh | Overiteľné kritériá, dotknuté rozhrania a riziká | Doménové kontrakty, návrhové vzory, prístupové práva |
| Implementácia | Plán primeraný úlohe, opätovné použitie existujúceho riešenia | Architektúra, pracovný postup, konkrétne príkazy |
| Test | Reprodukcia, spätná väzba a hodnotenie práce agenta | Harness, povinné kontroly, syntetické vstupy |
| Review a vydanie | Dôkaz k nálezu, súhrn MR a plán obnovy | Požadované schválenia, CI, postup vydania a rollbacku |
| Údržba | Premena overeného zistenia na regresiu alebo pravidlo | Signály prevádzky, oprávnenia pri incidente, vlastník |

## Väčšia zmena

Dohodni výsledok a dôkaz úspechu. Použi projektový formát plánu a akceptačné kritériá. Pri audite alebo plánovaní zachovaj dohodnutý rozsah. V implementácii použi existujúce služby a testovacie pomôcky. Pri UI porovnaj výsledok s referenčnou obrazovkou. Pri overení dolož príkaz, argumenty, prostredie, výsledok a nepokryté kroky. Zachovaj pravidlá pre citlivé dáta aj pôvodný verdikt povinných kontrol pri filtroch či výnimkách kitu.

## Review a MR

Prečítaj pravidlá review v `AGENTS.md` a projektový `REVIEW.md`, prípadne `.claude/REVIEW.md`. Over zadanie, zmenené kontrakty, oprávnenia a chybové stavy. Nález podopri konkrétnym miestom a dopadom. V MR dolož pokrytie diffu pre jeho základ a tip. Pri relevantných zmenách a výbere 0 súborov či testov uveď v sekcii Ako overiť samostatný riadok `Pokrytie MR: neoverené`, skutočný počet a chýbajúci projektový dôkaz. Odlíš vlastnú kontrolu od nezávislého review. Delegovanie a publikovanie sa riadia zadaním.

## Použitie v tíme

- **Nový projekt.** Do stručného `AGENTS.md` ulož účel projektu, podmienky spustenia, overený príkaz a odkaz na CI, keď už existuje. Doplň doménové pravidlá, ktoré ovplyvňujú zmenu kódu.
- **Existujúci projekt.** Pri audite uveď pre každú relevantnú fázu jej súčasný zdroj, výsledok overenia, medzeru a navrhovanú opravu. Pri zavádzaní vyber konkrétnu opakujúcu sa chybu a over najmenšiu zmenu postupu na reprezentatívnej úlohe.
- **Väčšia zmena.** V existujúcom tikete alebo pláne prepoj požadovaný výsledok, akceptačný prípad, zmenu rozhraní, zvolený postup a dôkaz z harnessu. Ak sa menia oprávnenia, peniaze, osobné údaje alebo produkčné dáta, zaznamenaj tiež zachované podmienky, správanie pri zlyhaní a možnosť obnovy.
- **Odovzdanie a prevádzka.** Pomenuj verziu a prostredie, ktoré si skutočne overil. Rozlišuj lokálnu prípravu, commit, publikovanie a nasadenie. Pri incidente zachyť pozorovaný prejav, čas, diagnózu, výsledok zásahu a overenie po ňom. Účinok zmeny postupu posudzuj podľa opakovaných chýb alebo prepracovania na porovnateľných úlohách.

## Izolácia a hodnotenie práce

- Pri schválenom rozdelení práce prideľ vlastníctvo súborov a oddelený worktree. Skontroluj aj zdieľané databázy, porty a externé služby. Výsledok over cez reálnych volajúcich a kontrakty.
- V projektovom `AGENTS.md` zachovaj sekciu `Code Review Rules` a odkaz na existujúci `REVIEW.md`. Ak zmena požiadavky mení očakávaný výsledok testu, zdokumentuj dôvod. Pri nezmenenom kontrakte oprav príčinu zlyhania.
- Pokyny agenta hodnoť na typickej úlohe, konkrétnom minulom zlyhaní aj prípade, keď sa nemajú aktivovať. Zaznamenaj model, konfiguráciu a pozorovaný výsledok. Pre platený alebo plánovaný eval dohodni rozsah a rozpočet.
- Pri hodnotení zavedeného postupu použi dostupné časy a počty porovnateľných zmien, napríklad čas po overenie, počet znovuotvorených chýb alebo čas obnovy. Osobné preferencie patria do používateľových pokynov, tímové konvencie do projektu. Pri opakovanom probléme naprieč projektmi navrhni anonymný príklad pre kit.

Pri odovzdaní over pravidlá vlastníkov pre zmenené cesty vrátane dokumentácie. Ak projekt oddeľuje autora a schvaľovateľa, zmenu potvrdí oprávnený nezávislý vlastník. Pri prijatí kitu zachovaj chránené vetvy a prostredia, povinné kontroly CI, sandbox a rozsah oprávnení identity, ktorá vykonáva zásah.

## Výklad na príklade

Pri hlasovom výklade začni problémom používateľa a pokračuj cez fázy podľa jeho otázky. Diagram slučky vysvetli na jednom príklade. Pri oprave exportu tím najprv určí, ktoré riadky očakáva. Dohodne hraničný prípad, nájde existujúci exportér, overí chybu na syntetickom vstupe a opravu skontroluje cez bežný vstup aplikácie. Pri vydaní sleduje dohodnutý signál a zachová možnosť návratu. Ak podnet prišiel z incidentu, ponechá regresiu aj po jeho uzavretí.

Rozlíš praktiky pôvodného playbooku, ich tímovú adaptáciu a skutočne aktívne kontroly. Pokyn v súbore vedie prácu agenta. Povinný gate vynucuje harness, CI alebo platforma v rozsahu, kde je zapnutý.

Zdrojom fáz je [The AI-native SDLC playbook od Anthropicu](https://claude.com/resources/articles/the-ai-native-sdlc-playbook). Pôvod adaptovaných Claude skillov popisuje súbor `plugins/dev/PROVENANCE.md` v repozitári kitu.
