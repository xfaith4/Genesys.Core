async (page) => {
  const check=(value,message)=>{if(!value)throw new Error(message);};
  await page.setInputFiles('#file',{name:'bad.json',mimeType:'application/json',buffer:Buffer.from('{"wrong":"format"}')});
  await page.waitForFunction(()=>document.getElementById('notice').textContent.includes('Unable to load'));
  check((await page.locator('#result-count').textContent()).includes('120 of 120'),'Invalid import destroyed active investigation');
  await page.setInputFiles('#file','output/playwright/conversation-analysis-filtered.json');
  await page.waitForFunction(()=>document.getElementById('coverage').textContent.includes('Saved selection: 20'));
  check((await page.locator('#stats strong').allTextContents())[1]==='110.5','Saved selection statistics changed on import');
  await page.locator('#collection summary').click();
  await page.fill('#since','2026-09-01T00:00');await page.fill('#until','2026-10-01T00:00');await page.fill('#queue','queue-a');await page.fill('#user','user-a');await page.fill('#division','division-a');
  await page.getByRole('button',{name:'Build collection command',exact:true}).click();
  const command=await page.locator('#query-command').textContent();
  check(command.includes("-QueueId 'queue-a'")&&command.includes("-UserId 'user-a'")&&command.includes("-DivisionId 'division-a'")&&command.includes('2026-10-01T00:00:00.000Z'),'Collection command scope incorrect');
  return {invalidImportRetainsAnalysis:true,filteredReimport:20,scopeCommandCorrect:true};
}
