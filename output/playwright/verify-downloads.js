async (page) => {
  await page.getByRole('button', { name: 'Users', exact: true }).click();
  const search = page.getByRole('textbox', { name: 'Search all columns', exact: true });
  await search.fill('Alice');
  const report = page.getByRole('region', { name: 'Ad-hoc report', exact: true });
  const metricField = report.getByRole('combobox', { name: 'Metric field', exact: true });
  if (await metricField.count() === 0) await report.getByRole('button', { name: 'Add metric', exact: true }).click();
  await metricField.selectOption('name');
  const group = report.getByRole('button', { name: 'Department', exact: true });
  if (await group.getAttribute('aria-pressed') !== 'true') await group.click();
  const recordExport = page.getByRole('region', { name: 'Export', exact: true });
  for (const [region, file] of [[recordExport, 'users-filtered-after.json'], [report, 'users-report-after.json']]) {
    await region.getByRole('combobox', { name: 'Format', exact: true }).selectOption('json');
    const pending = page.waitForEvent('download');
    await region.getByRole('button', { name: 'Download 1 row', exact: true }).click();
    await (await pending).saveAs(`output/playwright/${file}`);
  }
  await report.scrollIntoViewIfNeeded();
  await page.screenshot({ path: 'output/playwright/27-report-after.png' });
  await page.getByRole('region', { name: 'Users', exact: true }).scrollIntoViewIfNeeded();
  await page.screenshot({ path: 'output/playwright/28-users-after.png' });
  return { passed: ['fresh filtered JSON download', 'fresh grouped report JSON download'] };
}
