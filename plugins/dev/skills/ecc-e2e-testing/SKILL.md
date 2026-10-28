---
name: ecc-e2e-testing
description: "Playwright E2E testy server-renderovaných appiek: POM, lokátory, login cez storageState, formuláre, flaky testy. Pri písaní, oprave a stabilizácii E2E."
paths:
  - "tests/e2e/**"
  - "**/*.spec.js"
  - "**/*.spec.ts"
  - "playwright.config.*"
---
<!-- prevzaté z ECC skills/e2e-testing/SKILL.md @ b92f181, upravené -->

# E2E testy (Playwright)

## Kedy
- nový alebo opravovaný Playwright test, page object, konfigurácia
- flaky test, test zelený lokálne a červený inde
- overenie kritickej cesty (prihlásenie, hlavný formulár, export, import)

## Zásady
- E2E len pre kritické cesty používateľa; detaily patria do unit/integračných testov
- testuj **efekt**, nie len HTTP 200: JS nad prázdnou kolekciou (jQuery) nehádže, formulár zlyhá ticho → over zmenu v DOM, flash správu, nový riadok v zozname
- každý test samostatný: vlastné dáta, žiadna závislosť na poradí; zdieľaná DB → `workers: 1` alebo unikátne dáta (`Date.now()` v názve)
- žiadne `waitForTimeout()` — čakaj na stav (`await expect(…).toBeVisible()`, `toHaveURL`, `waitForResponse`)
- testy, ktoré menia dáta, oddeľ do vlastného Playwright projektu zapnutého env premennou (napr. `E2E_WRITE=1`) a púšťaj ich na snímke DB, ktorú potom vrátiš

## Lokátory (v tomto poradí)
1. `getByRole('button', { name: 'Uložiť' })`, `getByLabel('E-mail')`, `getByText(…)` — tak, ako stránku vidí používateľ aj čítačka
2. `data-testid` alebo `data-*` kotva, ktorú JS appky už používa
3. sémantická trieda (`.flash-success`, `table.list`)
- nikdy: pozičné selektory (`nth-child`, `.nth(3)`), dlhé CSS reťazce podľa vnorenia, XPath
- pred zmenou markupu: `grep` lokátorov v `tests/e2e/` — rovnaké kotvy používa aj JS appky

## Server-renderované stránky
- odoslanie formulára = POST → redirect → GET: po kliku `await expect(page).toHaveURL(/…/)`, potom over flash správu
- AJAX signál (Nette `?do=`, naja, Symfony UX): sľub pred klikom, `await` po ňom
  `const resp = page.waitForResponse(r => r.url().includes('do=') && r.ok()); await btn.click(); await resp;`
- `confirm()` dialóg: `page.once('dialog', d => d.accept())` **pred** klikom
- export (CSV/XLS/PDF): `const dl = page.waitForEvent('download')` pred klikom → `(await dl).suggestedFilename()`
- upload: `page.getByLabel('Súbor').setInputFiles('tests/e2e/fixtures/vzor.xml')`
- widgety (Select2, Chosen, datepicker) skrývajú natívny prvok → ovládaj ich UI ako používateľ (klik, písanie, výber) a over zobrazenú hodnotu
- CSRF: formulár cez UI pošle token sám; priamy `request.post()` bez tokenu zlyhá — to je správne správanie appky

## Prihlásenie
- `auth.setup.ts` ako projekt `setup`: prihlási sa raz, uloží `storageState` do `.auth/state.json`; ostatné projekty majú `dependencies: ['setup']` + `use.storageState`
- meno a heslo z env premenných (lokálny súbor mimo gitu); chýbajú → `setup.skip(true, 'dôvod')`, nie pád
- `.auth/` v `.gitignore`; heslo nikdy v kóde, logu ani screenshote
- MFA: testovací účet bez MFA alebo TOTP tajomstvo v env; nikdy reálne telefónne číslo
- opakované zlé heslo môže zamknúť účet → pri páde setupu nespúšťaj testy v slučke

## Page Object Model
- lokátory v konštruktore, akcie ako metódy; biznis asercie v teste, POM len čaká na stav
```typescript
import { Page, Locator, expect } from '@playwright/test';

export class ListPage {
  readonly search: Locator;
  readonly rows: Locator;

  constructor(readonly page: Page) {
    this.search = page.getByLabel('Názov');
    this.rows = page.locator('table.list tbody tr');
  }

  async goto() {
    await this.page.goto('/items/');
  }

  async searchBy(text: string) {
    await this.search.fill(text);
    await this.page.getByRole('button', { name: 'Hľadať' }).click();
    await expect(this.page).toHaveURL(/q=/);
  }
}
```

## Štruktúra testu
```typescript
import { test, expect } from '@playwright/test';
import { ListPage } from './pages/ListPage';

test.describe('Vyhľadávanie', () => {
  let list: ListPage;

  test.beforeEach(async ({ page }) => {
    list = new ListPage(page);
    await list.goto();
  });

  test('nájde záznam podľa názvu', async () => {
    await list.searchBy('Novák');
    await expect(list.rows.first()).toContainText('Novák');
  });

  test('bez výsledku ukáže hlášku', async ({ page }) => {
    await list.searchBy('xyz-neexistuje');
    await expect(list.rows).toHaveCount(0);
    await expect(page.getByText('Nenašli sa žiadne záznamy')).toBeVisible();
  });
});
```

## Konfigurácia — podstatné
```typescript
import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: '.',
  fullyParallel: false,
  workers: 1,
  retries: process.env.CI ? 1 : 0,
  forbidOnly: !!process.env.CI,
  reporter: 'list',
  use: {
    baseURL: process.env.E2E_BASE_URL || 'http://localhost:8080',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
  },
  projects: [
    { name: 'setup', testMatch: /auth\.setup\.ts/ },
    { name: 'chromium', dependencies: ['setup'], use: { storageState: '.auth/state.json' } },
  ],
});
```
- `baseURL` z env, nie natvrdo; jeden prehliadač stačí, kým appka nemá prehliadačovo citlivý kód

## Spúšťanie
- projektový príkaz má prednosť (`make test-e2e` a pod.) — prenesie env s prihlasovacími údajmi
- jeden test: `npx playwright test search.spec.ts -g "nájde záznam"`
- ladenie: `--headed`, `--debug`, `--ui`; po páde `npx playwright show-trace test-results/<test>/trace.zip`
- Playwright zvyčajne beží na hostiteľovi proti appke v Dockeri (`baseURL`), nie v PHP kontajneri

## Flaky testy
- potvrď: `npx playwright test <súbor> --repeat-each=10 --workers=1`; s `--trace on` porovnaj zelený a červený beh

| Príčina | Oprava |
|---|---|
| klik skôr, než JS naviaže handler | čakaj na stav, ktorý JS vytvára (inicializovaný widget), nie `waitForTimeout` |
| asercia bez auto-retry `expect(await loc.count()).toBe(0)` | web-first `await expect(loc).toHaveCount(0)` |
| zdieľané dáta, poradie testov | vlastné dáta na test, `workers: 1` |
| AJAX prekreslenie (snippet) počas akcie | `waitForResponse` na signál, potom ďalšia akcia |
| animácia (modal, collapse) | `await expect(modal).toBeVisible()` pred klikom dovnútra |
| `networkidle` pri pollingu/analytike | nečakaj na sieť, čakaj na konkrétny prvok |
- karanténa len s odkazom na úlohu: `test.fixme(true, '#123 flaky — dôvod')`; oprava má prednosť pred `retries`

## Výstup
- prvý riadok: `E2E: PASS|FAIL · <ok>/<spolu> · <n> flaky`
- pády: `súbor.spec.ts:45 — čo zlyhalo → pravdepodobná príčina / oprava`
- artefakty: cesta k trace/screenshotu (`test-results/…`), nie ich obsah
- testové dáta ostali v DB → povedz, ako ich vrátiť
