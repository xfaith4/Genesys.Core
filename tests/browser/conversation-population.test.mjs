import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
const context = vm.createContext({});
vm.runInContext(readFileSync(new URL('../../apps/ConversationAnalysis/population.js', import.meta.url), 'utf8'), context);
const engine = context.GcPopulation;
const rows = [
  {ConversationId:'a', DivisionIds:['d1','d2','d1'], ErrorCodes:['E1'], ErrorEvents:[{Code:'E1'},{Code:'E1'}], EndpointMinMos:0, tHandleSec:100, Answered:false},
  {ConversationId:'b', DivisionIds:['d1'], ErrorCodes:['E1','E2'], ErrorEvents:[{Code:'E1'},{Code:'E2'}], EndpointMinMos:4, tHandleSec:200, Answered:true},
  {ConversationId:'c', DivisionIds:['d2'], ErrorCodes:[], ErrorEvents:[], EndpointMinMos:null, tHandleSec:null, Answered:false},
];
test('filtering preserves zeros, false and array membership',()=>{
 assert.equal(engine.filterProfiles(rows,[{field:'EndpointMinMos',operator:'lt',value:'1'}]).length,1);
 assert.equal(engine.filterProfiles(rows,[{field:'Answered',operator:'equals',value:'false'}]).length,2);
 assert.equal(engine.filterProfiles(rows,[{field:'DivisionIds',operator:'equals',value:'d2'}]).length,2);
 assert.equal(engine.filterProfiles(rows,[{field:'ErrorCodes',operator:'exists'}]).length,2);
 assert.equal(engine.filterProfiles(rows,[{field:'EndpointMinMos',operator:'lt',value:''}]).length,0);
});
test('average/max/count cover all matching rows, exclude nulls, and retain missing count',()=>{
 const result=engine.stats(rows,'EndpointMinMos');
 assert.equal(result.average,2);assert.equal(result.max,4);assert.equal(result.validCount,2);assert.equal(result.missingCount,1);
 const many=Array.from({length:120},(_,i)=>({ConversationId:String(i),tHandleSec:i+1}));
 assert.equal(engine.stats(many,'tHandleSec').average,60.5);assert.equal(engine.stats(many,'tHandleSec').max,120);
 assert.equal(engine.stats([],'tHandleSec').average,null);
});
test('multi-membership grouping deduplicates each conversation within a group',()=>{
 const groups=engine.groupStats(rows,'DivisionIds','tHandleSec');
 const d1=groups.find(g=>g.group==='d1');assert.equal(d1.conversations,2);assert.equal(d1.average,150);
 const d2=groups.find(g=>g.group==='d2');assert.equal(d2.conversations,2);assert.equal(d2.validCount,1);
});
test('errors distinguish affected conversations from segment occurrences',()=>{
 const errors=engine.errorStats(rows);const e1=errors.find(e=>e.code==='E1');assert.equal(e1.conversations,2);assert.equal(e1.occurrences,3);
});
test('CSV escapes quotes, multi-value fields and spreadsheet formulas',()=>{
 const csv=engine.csv([{ConversationId:'=HYPERLINK("x")',DivisionIds:['d1','d2'],tHandleSec:-1}],['ConversationId','DivisionIds','tHandleSec']);
 assert.ok(csv.includes("'=HYPERLINK"));assert.ok(csv.includes('d1 | d2'));assert.ok(csv.includes('"-1"'));
});
test('import rejects mismatched formats and duplicate profile identities',()=>{
 assert.throws(()=>engine.validateBundle({profiles:rows}));
 assert.throws(()=>engine.validateBundle({kind:'genesys-conversation-analysis',schemaVersion:1,coverage:{},definitions:{numericFields:[]},profiles:[rows[0],rows[0]]}));
});
test('large populations retain full statistics and high-cardinality groups',()=>{
 const population=Array.from({length:50000},(_,i)=>({ConversationId:String(i),AgentKeys:['a'+(i%10000)],AgentNames:['Engineer '+(i%10000)],tHandleSec:i%120}));
 const groups=engine.groupStats(population,'AgentKeys','tHandleSec');
 assert.equal(groups.length,10000);
 assert.equal(groups.reduce((sum,g)=>sum+g.conversations,0),50000);
 const filtered=engine.filterProfiles(population,[{field:'tHandleSec',operator:'gt',value:100}]);
 assert.equal(filtered.length,7904);assert.equal(engine.stats(filtered,'tHandleSec').average,110);
 assert.equal(engine.filterProfiles(population,[],'Engineer 42').length,555);
 assert.equal(engine.filterProfiles(population,[],'Engineer 43').length,555);
});
test('new bundle validation invalidates cached search text',()=>{
 const row={ConversationId:'cached',AgentNames:['Before']};
 assert.equal(engine.filterProfiles([row],[],'before').length,1);
 row.AgentNames=['After'];
 engine.validateBundle({kind:'genesys-conversation-analysis',schemaVersion:1,coverage:{},definitions:{numericFields:[]},profiles:[row]});
 assert.equal(engine.filterProfiles([row],[],'before').length,0);
 assert.equal(engine.filterProfiles([row],[],'after').length,1);
});
