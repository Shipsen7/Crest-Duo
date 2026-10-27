// SPDX-License-Identifier: MPL-2.0
// Optional real-browser test. Requires Playwright plus its Chromium installation.
// Always uses a disposable browser profile and synthetic pages; never opens CloudKit.
import {mkdtemp,rm} from 'node:fs/promises';import {tmpdir} from 'node:os';import {resolve,join} from 'node:path';import assert from 'node:assert/strict';
const {chromium}=await import(process.env.PLAYWRIGHT_MODULE??'playwright');
const extension=resolve('extension'),profile=await mkdtemp(join(tmpdir(),'fennavio-extension-'));
let context;
try {
    context=await chromium.launchPersistentContext(profile,{channel:'chromium',headless:true,
        args:[`--disable-extensions-except=${extension}`,`--load-extension=${extension}`,'--disable-background-networking','--no-first-run']});
    await context.route('https://example.org/**',route=>route.fulfill({contentType:'text/html',body:'<!doctype html><title>Synthetic test page</title><p>Fixture</p>'}));
    const worker=context.serviceWorkers()[0]??await context.waitForEvent('serviceworker');const id=new URL(worker.url()).host;
    const ui=await context.newPage();await ui.goto(`chrome-extension://${id}/ui/popup.html?expanded=1`);
    const result=await ui.evaluate(async()=>{
        const call=async(action,values={})=>{const result=await chrome.runtime.sendMessage({action,...values});if(!result?.ok)throw new Error(result?.error);return result.state;};
        const a=await chrome.tabs.create({url:'https://example.org/first',active:false});const b=await chrome.tabs.create({url:'https://example.org/second',active:false});
        const group=await chrome.tabs.group({tabIds:[a.id,b.id]});await chrome.tabGroups.update(group,{title:'Synthetic group',color:'blue'});
        let state=await call('capture');const space=Object.values(state.records).find(record=>record.kind==='space' && record.body.value.name==='Synthetic group');
        if(!space)throw new Error('Group not captured');await call('rename',{kind:'space',id:space.id,name:'Renamed group'});
        const actual=await chrome.tabGroups.get(group);if(actual.title!=='Renamed group')throw new Error('Rename not projected');
        await call('addFolder',{spaceID:space.id,name:'Saved folder'});state=await call('state');const folder=Object.values(state.records).find(record=>record.kind==='folder');
        await call('addTab',{spaceID:space.id,url:'https://example.org/saved',placement:'saved',folderID:folder.id});
        const before=(await chrome.tabs.query({})).length;state=await call('state');if((await chrome.tabs.query({})).length!==before)throw new Error('Saved tab opened unexpectedly');
        const bound=state.bindings.tabs[a.id];await chrome.tabs.remove(a.id);await new Promise(resolve=>setTimeout(resolve,100));state=await call('state');
        if(!state.records[`tab:${bound}`].isTombstone)throw new Error('Explicit close not recorded');
        return {spaces:Object.values(state.records).filter(r=>r.kind==='space' && !r.isTombstone).length,folder:folder.id,closeRecorded:true};
    });
    assert.equal(result.spaces,1);assert.equal(result.closeRecorded,true);
    console.log('Real Chromium smoke passed: group adoption, rename, saved folder/tab and explicit close. Synthetic profile; no CloudKit.');
} finally {if(context)await context.close();await rm(profile,{recursive:true,force:true});}
