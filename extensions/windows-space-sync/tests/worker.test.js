// SPDX-License-Identifier: MPL-2.0
import test from 'node:test';import assert from 'node:assert/strict';
import {FakeBrowser} from './fixtures/browser.js';
class Event {
    listeners=[];
    addListener(listener){this.listeners.push(listener);}
    emit(...args){for(const listener of this.listeners)listener(...args);}
}
class FakeChrome extends FakeBrowser {
    constructor(local={}) {
        super();this.id='fixture-extension';this.savedLocal=structuredClone(local);this.savedSession={};this.alarmMap=new Map();this.levels=[];
        for(const name of ['onRemoved','onCreated','onUpdated','onMoved','onAttached','onReplaced','onActivated'])this.tabs[name]=new Event();
        for(const name of ['onCreated','onUpdated','onMoved','onRemoved'])this.tabGroups[name]=new Event();
        const changed=new Event();
        const storageArea=(data,name)=>({get:async key=>structuredClone({[key]:data[key]}),set:async values=>{Object.assign(data,structuredClone(values));changed.emit(Object.fromEntries(Object.entries(values).map(([key,newValue])=>[key,{newValue}])),name);},remove:async key=>{delete data[key];},setAccessLevel:async value=>{this.levels.push([name,value.accessLevel]);}});
        this.storage={local:storageArea(this.savedLocal,'local'),session:storageArea(this.savedSession,'session'),onChanged:changed};
        this.alarms={get:async name=>this.alarmMap.get(name),create:async(name,value)=>this.alarmMap.set(name,value),onAlarm:new Event()};
        this.identity={getRedirectURL:path=>`https://fixture-extension.chromiumapp.org/${path}`,launchWebAuthFlow:async()=>{throw new Error('No real Apple login in fixture');}};
        this.runtime={id:this.id,getURL:path=>`chrome-extension://${this.id}/${path}`,onMessage:new Event(),onInstalled:new Event(),onStartup:new Event()};
        const create=this.tabs.create;this.tabs.create=async properties=>{const tab=await create(properties);this.tabs.onCreated.emit(tab);return tab;};
        const group=this.tabs.group;this.tabs.group=async properties=>{const id=await group(properties);this.tabGroups.onCreated.emit(await this.tabGroups.get(id));return id;};
        const update=this.tabs.update;this.tabs.update=async(id,properties)=>{const tab=await update(id,properties);this.tabs.onUpdated.emit(id,properties,tab);return tab;};
        const remove=this.tabs.remove;this.tabs.remove=async id=>{await remove(id);this.tabs.onRemoved.emit(id,{windowId:1,isWindowClosing:false});};
    }
    async message(message,sender={id:this.id,url:this.runtime.getURL('ui/popup.html')}) {
        return new Promise((resolve,reject)=>{
            let async=false;const respond=value=>resolve(value);
            for(const listener of this.runtime.onMessage.listeners)if(listener(message,sender,respond)===true)async=true;
            if(!async)resolve(undefined);
        });
    }
}
async function load(local) {const browser=new FakeChrome(local);globalThis.chrome=browser;await import(`../extension/worker.js?fixture=${Math.random()}`);return browser;}
test('service worker persists UI commands, handles its own native events and redacts auth',async()=>{
    const browser=await load();browser.runtime.onInstalled.emit();let response=await browser.message({action:'addSpace',name:'A'});assert.equal(response.ok,true);
    const space=Object.values(response.state.records).find(r=>r.kind==='space');
    response=await browser.message({action:'addTab',spaceID:space.id,url:'https://example.org/',placement:'current'});assert.equal(response.ok,true);
    response=await browser.message({action:'state'});assert.equal(Object.values(response.state.records).filter(r=>r.kind==='tab').length,1);assert.equal(browser.tabList.length,1);
    browser.savedSession.auth={token:'secret-bearer'};browser.savedLocal.workspace.account='private-account';browser.savedLocal.workspace.config.apiToken='private-api';
    response=await browser.message({action:'state'});const serialized=JSON.stringify(response);assert.equal(serialized.includes('secret-bearer'),false);assert.equal(serialized.includes('private-account'),false);assert.equal(serialized.includes('private-api'),false);
    assert.ok(browser.levels.some(([area,level])=>area==='local' && level==='TRUSTED_CONTEXTS'));assert.ok(browser.alarmMap.has('poll'));
});
test('external pages cannot dispatch mutations through extension messages',async()=>{
    const browser=await load();const response=await browser.message({action:'addSpace',name:'Injected'},{id:'evil',url:'https://evil.example/'});assert.equal(response,undefined);assert.equal(browser.savedLocal.workspace,undefined);
});
test('worker restart reloads persisted data without depending on in-memory state',async()=>{
    let browser=await load();await browser.message({action:'addSpace',name:'Survives'});const local=structuredClone(browser.savedLocal);
    browser=await load(local);const response=await browser.message({action:'state'});assert.equal(Object.values(response.state.records).filter(r=>r.kind==='space').length,1);assert.equal(response.state.pendingCount,1);
});
test('configuration changes cannot enable production writes or mix cloud namespaces',async()=>{
    const browser=await load();await browser.message({action:'state'});
    let response=await browser.message({action:'configure',config:{container:'iCloud.io.github.shipsen7.fennavio',environment:'production',zone:'CrestPrivate',writeEnabled:true}});assert.equal(response.ok,false);
    browser.savedLocal.workspace.cloudIdentity=JSON.stringify(['iCloud.io.github.shipsen7.fennavio','development','CrestReview-test']);
    response=await browser.message({action:'configure',config:{container:'iCloud.io.github.shipsen7.fennavio',environment:'production',zone:'CrestPrivate',writeEnabled:false}});assert.equal(response.ok,false);
});
