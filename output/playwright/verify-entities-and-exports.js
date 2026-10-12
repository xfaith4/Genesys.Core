async (page) => {
 const frame=page.frameLocator('iframe[title="Conversation investigation workbench"]');
 await frame.locator('#file').setInputFiles('output/conversation-analysis-scale/conversation-analysis/20261012T035527311Z-064b0494/analysis.json');
 await frame.locator('#result-count').filter({hasText:'1,000 of 1,000'}).waitFor();
 if(!(await frame.locator('#grid tbody tr').first().textContent()).includes('Demo queues'))throw new Error('Ops-resolved queue names missing');
 await frame.locator('#group').selectOption('DivisionIds');
 if(!(await frame.locator('#groups').textContent()).includes('Demo divisions'))throw new Error('Ops-resolved division names missing');
 await frame.locator('#collection summary').click();await frame.locator('#resolve-names').check();
 await frame.locator('#since').fill('2026-09-01T00:00');await frame.locator('#until').fill('2026-10-01T00:00');await frame.locator('#query-form button[type="submit"]').click();
 if(!(await frame.locator('#query-command').textContent()).includes('-ResolveEntityNames'))throw new Error('Name-resolution collection command missing');
 // Export immediately after a pending debounced search; provenance and records must agree.
 const [download]=await Promise.all([page.waitForEvent('download'),(async()=>{
   await page.frames().find(f=>f.parentFrame()===page.mainFrame()).evaluate(()=>{const input=document.getElementById('search');input.value='agent-1';input.dispatchEvent(new Event('input'));document.getElementById('export-json').click();});
 })()]);
 await download.saveAs('output/playwright/entities-pending-search-export.json');
 // High-cardinality errors are limited in the DOM but retained in the complete export.
 await page.frames().find(f=>f.parentFrame()===page.mainFrame()).evaluate(()=>{
   const profiles=bundle.profiles.slice(0,201).map((row,i)=>({...row,ErrorCodes:['unique-'+i],ErrorEvents:[{Code:'unique-'+i}]}));load({...bundle,profiles});
 });
 if(await frame.locator('#errors tr').count()!==100)throw new Error('Error DOM not capped');
 await frame.locator('#more-errors').click();if(await frame.locator('#errors tr').count()!==200)throw new Error('Error show-more failed');
 const [errorsDownload]=await Promise.all([page.waitForEvent('download'),frame.locator('#export-json').click()]);
 await errorsDownload.saveAs('output/playwright/entities-high-cardinality-errors.json');
 return {opsNameLabels:true,collectionCommand:true,pendingSearchExport:true,errorCodes:201,initialRenderedErrors:100,showMore:200};
}
