async (page) => {
  const axePath='/mnt/f/Development/Genesys.Core/Genesys.Core/apps/GenesysDataClient/node_modules/axe-core/axe.min.js';
  const audits=[];
  const audit=async(label,context)=>{
    await context.addScriptTag({path:axePath});
    const violations=await context.evaluate(async()=>{const r=await axe.run(document,{runOnly:{type:'tag',values:['wcag2a','wcag2aa','wcag21a','wcag21aa']}});return r.violations.map(v=>({id:v.id,targets:v.nodes.map(n=>n.target)}));});
    audits.push({label,violations});
  };
  await audit('Atlas desktop shell',page);
  await audit('Embedded desktop workbench',page.frames()[1]);
  await page.setViewportSize({width:390,height:844});
  await audit('Atlas mobile shell',page);
  await audit('Embedded mobile workbench',page.frames()[1]);
  await page.setViewportSize({width:1440,height:1000});
  if(audits.some(a=>a.violations.length))throw new Error(JSON.stringify(audits));
  return audits;
}
