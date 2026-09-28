/**
 * WCAG 2.1 Level AA gate for the rendered application.
 *
 * The repository's PowerShell analyzer (scripts/Invoke-AccessibilityAudit.ps1) checks static HTML
 * surfaces. It cannot see this application, whose markup only exists once React has rendered it,
 * so this drives a real browser and runs axe-core against every skin, theme and accent instead.
 *
 * Accent shades are solved rather than eyeballed - see src/core/accents.ts - and every one of them
 * is audited here, because a palette that only passes for the default accent is not a passing
 * palette.
 *
 *   dotnet run --project tools/Genesys.MockServer     # in the repository root
 *   npm run test:a11y
 *
 * Skips with exit code 0 when no demo server is reachable, so it stays runnable offline.
 */

import { chromium } from 'playwright';
import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';

const require = createRequire(import.meta.url);
const axeSource = readFileSync(require.resolve('axe-core/axe.min.js'), 'utf8');

const BASE = process.env.GDC_MOCK_SERVER ?? 'http://localhost:7777';
const TAGS = ['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa'];
const ACCENT_COUNT = 5;

const reachable = await fetch(`${BASE}/health`, { signal: AbortSignal.timeout(2500) })
  .then((r) => r.ok)
  .catch(() => false);

if (!reachable) {
  console.warn(`\n  SKIPPING accessibility audit: no demo server at ${BASE}\n`);
  process.exit(0);
}

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1500, height: 950 } });

let failures = 0;
let audited = 0;

const audit = async (label) => {
  // Park the pointer so hover styles are not what gets measured.
  await page.mouse.move(2, 2);
  await page.waitForTimeout(120);
  await page.addScriptTag({ content: axeSource });
  const result = await page.evaluate(
    async (tags) => await window.axe.run(document, { runOnly: { type: 'tag', values: tags } }),
    TAGS,
  );
  audited += 1;

  if (result.violations.length === 0) {
    console.log(`  PASS  ${label}`);
    return;
  }

  failures += result.violations.length;
  console.log(`  FAIL  ${label}`);
  for (const violation of result.violations) {
    for (const node of violation.nodes) {
      const why = (node.any[0]?.message ?? node.all[0]?.message ?? '').replace(/\s+/g, ' ');
      console.log(`        ${violation.id} :: ${node.target.join(' ')}`);
      console.log(`          ${why}`);
    }
  }
};

/** Clears both stores so each surface is audited from a known state. */
const reset = async () => {
  await page.goto(BASE);
  await page.evaluate(() => {
    localStorage.clear();
    sessionStorage.clear();
  });
};

/** Completes the PKCE flow so the authenticated surfaces can be reached. */
const signIn = async () => {
  await page.goto(`${BASE}/`);
  await page.reload();
  await page.waitForSelector('.signin', { timeout: 30000 });
  await page.click('.signin__body button.btn--primary');
  await page.waitForSelector('button.approve', { timeout: 30000 });
  await page.click('button.approve');
  await page.waitForSelector('.gx-menu, .ax-rail', { timeout: 30000 });
};

/** Loads a route from a clean workspace. A hash-only change does not remount, so reload. */
const open = async (route, waitFor) => {
  await reset();
  await signIn();
  await page.goto(`${BASE}/${route}`);
  await page.reload();
  await page.waitForSelector(waitFor, { timeout: 30000 });
};

// The unauthenticated surfaces are audited first, from a clean store. The consent screen is
// served by the mock server rather than by React, but a user still has to read it.
console.log('\nWCAG 2.1 AA — authentication');
await reset();
await page.goto(`${BASE}/`);
await page.reload();
await page.waitForSelector('.signin', { timeout: 30000 });
await audit('sign in');

await page.click('.signin__body button.btn--primary');
await page.waitForSelector('button.approve', { timeout: 30000 });
await audit('demo authorization consent');
await page.click('button.approve');
await page.waitForSelector('.gx-menu', { timeout: 30000 });

console.log('\nWCAG 2.1 AA — Genesys skin');
await open('#/home', '.gx');
await audit('genesys · getting started');

await open('#/endpoints', '.endpoint');
await audit('genesys · endpoint explorer');

await open('#/explore/users', '.grid__row');
await audit('genesys · explorer');

console.log('\nWCAG 2.1 AA — Atlas skin, every theme and accent');
for (const theme of ['Light', 'Dark']) {
  for (let accent = 0; accent < ACCENT_COUNT; accent += 1) {
    await open('#/explore/conversations', '.gx');
    await page.click('.gx-avatar');
    await page.waitForSelector('.ax');
    await page.click(`.ax-seg__btn:has-text("${theme}")`);
    await page.click('.ax-gear');
    await page.waitForSelector('.ax-settings');
    const swatch = page.locator('.ax-swatch').nth(accent);
    const label = (await swatch.getAttribute('aria-label')) ?? String(accent);
    await swatch.click();
    await page.waitForSelector('.grid__row', { timeout: 30000 });
    await audit(`atlas · ${theme.toLowerCase()} · ${label.toLowerCase()}`);
  }
}

await browser.close();

console.log(
  `\n${failures === 0 ? 'PASS' : 'FAIL'} - ${audited} surface(s) audited, ${failures} violation(s).`,
);
process.exit(failures === 0 ? 0 : 1);
