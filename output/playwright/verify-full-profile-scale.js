async page => {
 const frame=page;
 const start=Date.now();await frame.locator('#file').setInputFiles('output/playwright/population-20000-full-profiles.json');
 await frame.locator('#result-count').filter({hasText:'20,000 of 20,000'}).waitFor({timeout:60000});
 const importWallMs=Date.now()-start;
 await frame.locator('#metric').selectOption('tHandleSec');
 const values=await frame.locator('#stats strong').allTextContents();
 if(values[1]!=='500.5'||values[3]!=='1,000')throw new Error('Full-profile population stats wrong: '+values);
 await frame.locator('#group').selectOption('DivisionIds');
 if(await frame.locator('#groups tr').count()!==2)throw new Error('Division counts wrong');
 await frame.locator('#search').fill('Demo users agent-1');await frame.locator('#result-count').filter({hasText:'4,000 of 20,000'}).waitFor();
 await frame.locator('#reset').click();
 return {population:20000,topLevelFields:99,averageHandle:500.5,max:1000,importWallMs,limitations:'Repeated 1000 fully normalized synthetic Ops profiles with unique IDs; no tenant data.'};
}
