async (page) => {
  await page.addScriptTag({path:'/mnt/f/Development/Genesys.Core/Genesys.Core/apps/GenesysDataClient/node_modules/axe-core/axe.min.js'});
  const audits=[];
  const audit=async label=>{const result=await page.evaluate(async()=>await axe.run(document,{runOnly:{type:'tag',values:['wcag2a','wcag2aa','wcag21a','wcag21aa']}}));audits.push({label,violations:result.violations.map(v=>({id:v.id,nodes:v.nodes.map(n=>n.target)}))});};
  await audit('desktop population');
  await page.locator('#grid tbody').getByRole('button').first().click();
  await audit('conversation detail dialog');
  await page.click('#close-detail');
  await page.setViewportSize({width:390,height:844});
  await audit('mobile population');
  await page.setViewportSize({width:1440,height:1000});
  if(audits.some(a=>a.violations.length))throw new Error(JSON.stringify(audits));
  return audits;
}
