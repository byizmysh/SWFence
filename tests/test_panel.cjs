'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../packages/luci-app-swfence/htdocs/luci-static/resources/view/swfence/overview.js'), 'utf8');
let state = {
 configuration_valid: true, configured_enabled: true, guard_present: true, config_matches: true,
 dns_running: true, http_running: true, last_error: '',
 version:'0.3.0', project_url:'https://github.com/example/SWFence',
 domain_status:{state:'updated',resolved:'1',unresolved:'0',error:''},
 counters: {inet_dropped:'4', bridge_dropped:'12'},
 daily_counters: {available:true,day:'2026-10-28',timezone:'MSK +0300',collected_since:'1793142000',collected_since_local:'2026-10-28 00:00:00 MSK',inet_dropped:'4',bridge_dropped:'12'},
 config: {enabled:'1', macs:['02:00:00:00:00:11'], router_ip:'192.168.50.1', lan_subnet:'192.168.50.0/24',allowed_ips:['1.1.1.1'],allowed_domains:['example.com']}
};
let configureArgs;
let readonly = false;
let statusError = false;
let pendingStatus;
let diagnosticsError = false;
let diagnosticsCalls = 0;
let pendingDiagnostics;
let pendingConfigure;
let configureCalls=0;
let configureResult={ok:true,message:'Applied'};
let configureError=false;
let configureStatusError=false;
let saveError=false;
const polls = [];
const E = (tag, attrs, children) => ({tag, attrs:attrs || {}, disabled:!!(attrs || {}).disabled, children: children == null ? [] : Array.isArray(children) ? children : [children],
 listeners:{}, addEventListener(name,fn){this.listeners[name]=fn;},
 setAttribute(name,value){this.attrs[name]=value;},removeAttribute(name){delete this.attrs[name];},
 classList:{toggle(){}}
});
const nodes = n => n && typeof n === 'object' ? [n, ...n.children.flatMap(nodes)] : [];
const text = n => typeof n === 'string' ? n : n && typeof n === 'object' ? n.children.map(text).join(' ') : '';
class JSONMap {
 constructor(data) {this.config = structuredClone(data); this.data = {get:(_, key) => this.config[key]};}
 section() {return {option:()=>({depends:()=>{}}), addremove:false};}
 render() {return Promise.resolve(E('form',{},'Settings'));}
 save(fn) {return saveError ? Promise.reject(new Error('Invalid form value')) : Promise.resolve().then(fn);}
}
const dom = {content:(target, value)=>{target.children = Array.isArray(value) ? value : [value];}};
const notifications=[];
const ui={createHandlerFn:(owner,fn)=>fn.bind(owner), addNotification:(_,node,type)=>notifications.push({text:text(node),type})};
const rpc={declare:desc=>(...args)=>{
 if(desc.method==='status') return statusError ? Promise.reject(new Error('Disconnected')) : pendingStatus || Promise.resolve(structuredClone(state));
 if(desc.method==='diagnostics') {
  diagnosticsCalls++;
  if (pendingDiagnostics) return pendingDiagnostics;
  if (diagnosticsError) return Promise.reject(new Error('Disconnected'));
  return Promise.resolve({scope:'Router-local checks only',checks:[{name:'console_external_isolation',result:'manual',detail:'Verify from console'}]});
 }
 configureArgs=args; configureCalls++;
 if(configureError) return Promise.reject(new Error('Disconnected'));
 if(configureStatusError) statusError=true;
 return pendingConfigure || Promise.resolve(configureResult);
}};
const view = new Function('view','form','rpc','poll','ui','dom','E','_','L',source)(
 {extend:x=>x},{JSONMap,NamedSection:0,Flag:0,DynamicList:0,Value:0},rpc,
 {add:(f,interval)=>polls.push({run:f,interval})},ui,dom,E,s=>s,{hasViewPermission:()=>!readonly});
(async()=>{
 let tree = await view.render(await view.load());
 assert.match(text(tree), /Rules loaded — verify console isolation/);
 assert.doesNotMatch(text(tree), /Isolation verified/);
 assert.match(text(tree), /Dropped today on bridge/);
 assert.match(text(tree), /2026-10-28 · MSK \+0300/);
 assert.equal(nodes(tree).filter(n=>n.tag==='h2' && n.children.some(c=>c.tag==='strong' && text(c)==='SWFence')).length,1);
 assert.equal(nodes(tree).find(n=>n.tag==='a' && text(n)==='GitHub').attrs.href,'https://github.com/example/SWFence');
 const button = label=>nodes(tree).find(n=>n.tag==='button' && text(n)===label);
 assert.deepEqual(polls.map(p=>p.interval), [5,15]);
 const statusPoll = polls[0].run, diagnosticsPoll = polls[1].run;
 await diagnosticsPoll();
 assert.equal(diagnosticsCalls,0);
 await button('Start live diagnostics').attrs.click();
 assert.match(text(tree), /ON CONSOLE/);
 assert.doesNotMatch(text(tree), /MANUAL/);
 assert.match(text(tree), /Router-local checks only/);
 assert.match(text(tree), /Last check:/);
 await diagnosticsPoll();
 assert.equal(diagnosticsCalls,2);
 let resolveDiagnostic;
 pendingDiagnostics = new Promise(resolve=>{resolveDiagnostic=resolve;});
 const firstDiagnostic = diagnosticsPoll();
 const secondDiagnostic = diagnosticsPoll();
 assert.equal(diagnosticsCalls,3,'Overlapping polls must share one request');
 resolveDiagnostic({scope:'Router-local checks only',checks:[]});
 await Promise.all([firstDiagnostic,secondDiagnostic]);
 pendingDiagnostics = null;
 diagnosticsError=true;
 await diagnosticsPoll();
 assert.match(text(tree), /Diagnostics unavailable: Disconnected/);
 assert.doesNotMatch(text(tree), /Last check:/,'A failed refresh must not leave stale results visible');
 diagnosticsError=false;
 await button('Stop live diagnostics').attrs.click();
 await diagnosticsPoll();
 assert.equal(diagnosticsCalls,4);
 assert.match(text(tree), /Automatic diagnostics paused/);
 state.daily_counters.inet_dropped='6'; state.daily_counters.bridge_dropped='17';
 await statusPoll();
 assert.match(text(tree), /Bridge: \+5 \/ Routed: \+2/);
 await statusPoll();
 assert.match(text(tree), /Bridge: \+0 \/ Routed: \+0/);
 state.daily_counters.inet_dropped='0'; state.daily_counters.bridge_dropped='0';
 await statusPoll();
 assert.match(text(tree), /Counters reset/);
 state.daily_counters.day='2026-10-29';
 state.daily_counters.collected_since='1793228400';
 await statusPoll();
 assert.match(text(tree), /New day/);
 state.daily_counters.collected_since='1793228405';
 await statusPoll();
 assert.match(text(tree), /Collection restarted/);
 statusError=true;
 await statusPoll();
 assert.match(text(tree), /Status unavailable: Disconnected/);
 assert.doesNotMatch(text(tree), /Last status update/);
 statusError=false;
 await statusPoll();
 assert.match(text(tree), /Waiting for next update/);
 await button('Apply protection settings').attrs.click();
 assert.equal(configureArgs.length,8);
 assert.equal(configureArgs[1],'02:00:00:00:00:11');
 assert.deepEqual(configureArgs.slice(6), ['1.1.1.1','example.com']);
 assert.match(text(tree), /Settings applied\./);
 const apply=button('Applied');
 const form=nodes(tree).find(n=>n.tag==='form');
 assert.equal(apply.disabled,false);
 form.listeners.input();
 assert.equal(text(apply),'Apply protection settings');
 assert.match(text(tree), /Unsaved changes/);
 let resolveConfigure;
 pendingConfigure=new Promise(resolve=>{resolveConfigure=resolve;});
 const beforeCalls=configureCalls;
 const pendingApply=apply.attrs.click();
 const duplicateApply=apply.attrs.click();
 assert.equal(pendingApply,duplicateApply);
 assert.equal(apply.disabled,true);
 assert.equal(apply.attrs['aria-busy'],'true');
 assert.equal(form.attrs.inert,'');
 assert.equal(text(apply),'Applying…');
 await new Promise(setImmediate);
 assert.equal(configureCalls,beforeCalls+1);
 let resolveStatus;
 pendingStatus=new Promise(resolve=>{resolveStatus=resolve;});
 resolveConfigure({ok:true,message:'Applied'});
 await new Promise(setImmediate);
 assert.equal(text(apply),'Verifying…');
 assert.match(text(tree), /Checking router status/);
 resolveStatus(structuredClone(state));
 await pendingApply;
 pendingStatus=null;
 pendingConfigure=null;
 assert.equal(text(apply),'Applied');
 assert.equal(apply.disabled,false);
 assert.equal(apply.attrs['aria-busy'],'false');
 assert.equal(form.attrs.inert,undefined);
 configureResult={ok:false,message:'Previous settings restored.'};
 await apply.attrs.click();
 assert.match(text(tree), /Settings were not applied\.\s+Previous settings restored\./);
 assert.equal(text(apply),'Try again');
 configureResult={ok:true,message:'Applied'};
 configureError=true;
 await apply.attrs.click();
 assert.match(text(tree), /Apply could not be confirmed/);
 assert.doesNotMatch(text(tree), /Settings applied\./);
 configureError=false;
 configureStatusError=true;
 await apply.attrs.click();
 assert.match(text(tree), /Settings accepted; confirmation unavailable/);
 assert.equal(apply.disabled,false);
 configureStatusError=false; statusError=false;
 state.config.router_ip='192.168.50.99';
 await apply.attrs.click();
 assert.match(text(tree), /Apply not confirmed/);
 assert.doesNotMatch(text(tree), /Settings applied\./);
 state.config.router_ip='192.168.50.1';
 saveError=true;
 const beforeValidation=configureCalls;
 await apply.attrs.click();
 assert.equal(configureCalls,beforeValidation);
 assert.match(text(tree), /Settings were not sent/);
 assert.equal(form.attrs.inert,undefined);
 saveError=false;
 state.config_matches = false;
 await statusPoll();
 assert.match(text(tree), /Settings not applied/);
 state.config_matches = true; state.guard_present = false;
 await statusPoll();
 assert.match(text(tree), /Guard rules missing/);
 state.guard_present = true; state.dns_running=false;
 await statusPoll();
 assert.match(text(tree), /local service unavailable/);
 state.last_error='<script>alert(1)</script>';
 await statusPoll();
 assert.match(text(tree), /Last apply failed/);
 assert.equal(nodes(tree).filter(n=>n.tag==='script').length,0);
 readonly=true;
 state.project_url='javascript:alert(1)';
 tree=await view.render(await view.load());
 assert.equal(nodes(tree).filter(n=>n.tag==='a').length,0,'An untrusted project URL must not become a link');
 assert.equal(button('Apply protection settings').attrs.disabled,true);
 console.log('Panel tests passed: apply progress/confirmation, unsaved edits, duplicate clicks, backend/connection/validation errors, live diagnostics, counters, text escaping and read-only UI.');
})().catch(e=>{console.error(e);process.exitCode=1;});
