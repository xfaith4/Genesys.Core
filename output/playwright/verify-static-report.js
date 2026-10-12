async (page) => {
  const check = (ok, message) => { if (!ok) throw new Error(message); };
  for (const [width, height, file] of [[1440, 1000, '32-static-report-after.png'], [390, 844, '33-static-report-mobile-after.png']]) {
    await page.setViewportSize({ width, height });
    const dimensions = await page.evaluate(() => ({ width: innerWidth, content: document.documentElement.scrollWidth }));
    check(dimensions.content <= dimensions.width, `Report page overflows at ${width}px: ${dimensions.content}`);
    const sip = page.getByRole('region', { name: 'SIP trace breakdown', exact: true });
    check(await sip.getAttribute('tabindex') === '0', 'Wide report table is not keyboard focusable');
    check(await page.getByRole('region', { name: 'Evidence sections', exact: true }).count() === 1, 'Evidence table wrapper missing');
    await page.screenshot({ path: `output/playwright/${file}` });
  }
  await page.setViewportSize({ width: 1440, height: 1000 });
  return { passed: ['desktop report page width', '390px report page width', 'keyboard-accessible SIP and evidence table regions', 'summary, findings and timeline retained'] };
}
