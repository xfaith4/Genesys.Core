// Repeatable frontend-engine benchmark. Synthetic normalized profiles; no tenant calls.
import { readFileSync, writeFileSync } from 'node:fs';
import vm from 'node:vm';
import { performance } from 'node:perf_hooks';
const size=Number(process.argv[2] ?? 50000);
if(!Number.isInteger(size)||size<1||size>500000)throw new Error('Population must be 1..500000');
const context=vm.createContext({});
vm.runInContext(readFileSync(new URL('../apps/ConversationAnalysis/population.js',import.meta.url),'utf8'),context);
const engine=context.GcPopulation;
const rows=Array.from({length:size},(_,i)=>({
 ConversationId:`conversation-${i}`,StartUtc:'2026-09-15T12:00:00Z',Direction:i%3?'inbound':'outbound',
 DivisionIds:[`division-${i%12}`],QueueIds:[`queue-${i%300}`,`queue-${(i+1)%300}`],AgentKeys:[`agent-${i%10000}`],UserIds:[`agent-${i%10000}`],
 QueueNames:[`Support ${i%300}`,`Support ${(i+1)%300}`],AgentNames:[`Engineer ${i%10000}`],
 tHandleSec:i%120,EndpointMinMos:i%7?2+(i%200)/100:null,
 ErrorCodes:i%4?[]:['demo.error'],ErrorEvents:i%4?[]:[{Code:'demo.error'},{Code:'demo.error'}],
 Sessions:[{Metrics:{tHandle:(i%120)*1000},UserId:`agent-${i%10000}`}],
 Timeline:Array.from({length:4},(_,j)=>({StartUtc:'2026-09-15T12:00:00Z',SegmentType:'interact',QueueId:`queue-${i%300}`,SessionId:`s-${j}`})),
}));
const timings={};
const measure=(name,fn)=>{const start=performance.now();const result=fn();timings[name]=Math.round((performance.now()-start)*100)/100;return result;};
measure('validateMs',()=>engine.validateBundle({kind:'genesys-conversation-analysis',schemaVersion:1,coverage:{},definitions:{numericFields:['tHandleSec']},profiles:rows}));
const filtered=measure('numericFilterMs',()=>engine.filterProfiles(rows,[{field:'tHandleSec',operator:'gt',value:100}]));
const searched=measure('firstSearchMs',()=>engine.filterProfiles(rows,[],'engineer 42'));
measure('repeatSearchMs',()=>engine.filterProfiles(rows,[],'engineer 43'));
const stats=measure('statsMs',()=>engine.stats(filtered,'tHandleSec'));
const groups=measure('groupMs',()=>engine.groupStats(rows,'AgentKeys','tHandleSec'));
const errors=measure('errorsMs',()=>engine.errorStats(rows));
const report={kind:'synthetic-population-engine-benchmark',node:process.version,population:size,filtered:filtered.length,searched:searched.length,groups:groups.length,errors,stats,timings,heapUsedMiB:Math.round(process.memoryUsage().heapUsed/1048576),limitations:'Engine-only, synthetic profiles, local machine. Excludes browser DOM, import parsing, Ops profiling, network and export serialization.'};
if(process.argv[4]) {
 const entities={queues:{},users:{},divisions:{}};
 for(const row of rows){for(let i=0;i<row.QueueIds.length;i++)entities.queues[row.QueueIds[i]]=row.QueueNames[i];entities.users[row.UserIds[0]]=row.AgentNames[0];entities.divisions[row.DivisionIds[0]]='Division '+row.DivisionIds[0].split('-')[1];}
 writeFileSync(process.argv[4],JSON.stringify({kind:'genesys-conversation-analysis',schemaVersion:1,generatedAtUtc:new Date().toISOString(),coverage:{status:'complete',evidenceMode:'synthetic'},definitions:{numericFields:['tHandleSec','EndpointMinMos'],nullPolicy:'Missing values remain null.',agentMetrics:'Synthetic seconds.',mos:'Synthetic endpoint minimum.'},entityResolution:{enabled:true,entities,coverage:{},definition:'Synthetic benchmark labels'},profiles:rows}));
}
if(process.argv[3])writeFileSync(process.argv[3],JSON.stringify(report,null,2));
console.log(JSON.stringify(report,null,2));
