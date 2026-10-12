async (page) => {
  const title = await page.title();
  if (!title.includes('Monthly voice volume')) throw new Error('Report title missing');
  const sourceRows = await page.locator('[aria-label="Source coverage"] tr').count();
  if (sourceRows !== 5) throw new Error('Expected four independent source rows');
  const highlighted = await page.locator('td.difference').count();
  if (highlighted === 0) throw new Error('Differences not highlighted');
  const summary = await (await page.request.get(new URL('summary.json', page.url()).href)).json();
  if (summary.evidenceMode !== 'synthetic' || summary.sources.length !== 4) throw new Error('Evidence metadata missing');
  for (const viewport of [{ width: 1440, height: 1000 }, { width: 390, height: 844 }]) {
    await page.setViewportSize(viewport);
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth);
    if (overflow) throw new Error(`Page overflows at ${viewport.width}px`);
  }
  await page.setViewportSize({ width: 1440, height: 1000 });
  await page.screenshot({ path: 'output/playwright/monthly-volume-report.png', fullPage: true });
  return { sourceRows: 4, highlighted, evidenceMode: summary.evidenceMode, mobileOverflow: false };
}
