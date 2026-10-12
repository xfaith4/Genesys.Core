async (page) => {
  const frame=()=>page.frameLocator('iframe[title="Conversation investigation workbench"]');
  await frame().locator('#reset').click();
  await frame().locator('#next').click();
  await frame().getByText('Choose columns',{exact:true}).click();
  const column=frame().locator('#columns label').filter({hasText:/^DurationSec$/}).locator('input');
  await column.check();
  await page.getByRole('button',{name:'Getting started',exact:true}).click();
  await page.goBack();
  await frame().locator('#page').waitFor();
  if(!(await frame().locator('#page').textContent()).includes('2 of 3'))throw new Error('Pagination lost on Back');
  if(!await frame().locator('#columns label').filter({hasText:/^DurationSec$/}).locator('input').isChecked())throw new Error('Column control lost on Back');
  if(!(await frame().locator('#grid thead').textContent()).includes('DurationSec'))throw new Error('Column lost on Back');
  await page.getByRole('button',{name:'Genesys skin',exact:true}).click();
  await frame().locator('#page').waitFor();
  if(!(await frame().locator('#page').textContent()).includes('2 of 3'))throw new Error('Pagination lost on skin switch');
  await page.addScriptTag({path:'/mnt/f/Development/Genesys.Core/Genesys.Core/apps/GenesysDataClient/node_modules/axe-core/axe.min.js'});
  const audit=await page.evaluate(async()=>{const r=await axe.run(document,{runOnly:{type:'tag',values:['wcag2a','wcag2aa','wcag21a','wcag21aa']}});return r.violations.map(v=>v.id);});
  if(audit.length)throw new Error(JSON.stringify(audit));
  await frame().locator('#file').setInputFiles({name:'invalid.json',mimeType:'application/json',buffer:Buffer.from('{}')});
  await frame().locator('#notice').filter({hasText:'Unable to load'}).waitFor();
  if(!(await frame().locator('#result-count').textContent()).includes('120 of 120'))throw new Error('Invalid import lost investigation');
  await frame().locator('#previous').click();
  return {backRetention:true,paginationRetention:true,columnRetention:true,invalidImportPreservesAnalysis:true,genesysShellViolations:audit};
}
