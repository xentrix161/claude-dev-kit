# JavaScript a rozhranie

- Z manifestu modulu, lockfile a CI zisti, ako projekt testuje a zostavuje zmenený vstup. V aplikácii s viacerými balíkmi vyber vlastníka zmeny. Pri Symfony s AssetMapperom over projektový postup kompilácie a načítanie mapovaného modulu. Pri Webpacku alebo Vite vyber príslušný build podľa skriptov projektu.
- Pre zmenu logiky spusti dotknuté unit testy. Pri zmene väzby medzi Twig či Latte a JavaScriptom over jednu skutočnú interakciu s výsledným assetom, aj chybovú odpoveď, ak sa menila. Pri formulári over uložený výsledok alebo obnovený stav po načítaní stránky.
- Pri zmene serverového JavaScriptu alebo CLI over vstup cez projektový integračný test. Skontroluj zmenenú odpoveď alebo návratový kód a výsledný zápis. Pri TypeScripte použi existujúcu kontrolu typov.
- Pri zmene interakcie over klávesnicu, návrat fokusu a zobrazenie chyby. Použi existujúci komponent, syntetický účet a projektový prehliadačový harness. Zaznamenaj scenár a výsledok.
