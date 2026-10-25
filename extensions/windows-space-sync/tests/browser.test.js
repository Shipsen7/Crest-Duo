// SPDX-License-Identifier: MPL-2.0
import test from 'node:test';import assert from 'node:assert/strict';
import {Workspace} from '../extension/core/workspace.js';import {BrowserProjection} from '../extension/browser/projection.js';
import {valueOf,keyOf} from '../extension/core/record.js';
class FakeBrowser {
    constructor() {
        this.tabList=[];this.groupList=[];this.closed=[];this.nextID=10;this.windowsList=[{id:1,incognito:false}];
        this.tabs={query:async()=>structuredClone(this.tabList),get:async id=>{const tab=this.tabList.find(t=>t.id===id);if(!tab)throw new Error('Tab missing');return structuredClone(tab);},
            create:async properties=>{const tab={id:this.nextID++,groupId:-1,index:this.tabList.length,windowId:1,incognito:false,pinned:false,title:new URL(properties.url).hostname,...properties};this.tabList.push(tab);return structuredClone(tab);},
            update:async(id,properties)=>{const tab=this.tabList.find(t=>t.id===id);Object.assign(tab,properties);if(tab.pinned)tab.groupId=-1;return structuredClone(tab);},
            remove:async id=>{this.closed.push(id);this.tabList=this.tabList.filter(t=>t.id!==id);},
            group:async properties=>{let groupId=properties.groupId;if(groupId===undefined){groupId=this.nextID++;this.groupList.push({id:groupId,title:'',color:'grey',windowId:1,incognito:false});}for(const id of properties.tabIds)this.tabList.find(t=>t.id===id).groupId=groupId;return groupId;},
            move:async(id,properties)=>{const index=this.tabList.findIndex(t=>t.id===id),[tab]=this.tabList.splice(index,1);if(properties.windowId!==undefined)tab.windowId=properties.windowId;this.tabList.splice(properties.index<0?this.tabList.length:properties.index,0,tab);this.tabList.forEach((t,i)=>t.index=i);return structuredClone(tab);}};
        this.tabGroups={query:async()=>structuredClone(this.groupList),get:async id=>structuredClone(this.groupList.find(g=>g.id===id)),update:async(id,props)=>Object.assign(this.groupList.find(g=>g.id===id),props)};
        this.windows={getAll:async()=>structuredClone(this.windowsList)};
    }
    group(title='Arbeit',id=1){const group={id,title,color:'blue',windowId:1,incognito:false};this.groupList.push(group);return group;}
    tab(url='https://example.org/',groupId=1,id=2){const tab={id,url,title:'Test',groupId,windowId:1,index:this.tabList.length,pinned:false,incognito:false};this.tabList.push(tab);return tab;}
}
async function fixture(){const workspace=new Workspace(),browser=new FakeBrowser();browser.group();browser.tab();let saves=0;const projection=new BrowserProjection(workspace,browser,async()=>{saves++;});await projection.observe({capture:true});return{workspace,browser,projection,saves:()=>saves};}
test('group creation/rename/color and tab navigation are captured with stable IDs',async()=>{
    const {workspace,browser,projection}=await fixture();const space=workspace.live('space')[0],tab=workspace.live('tab')[0];
    browser.groupList[0].title='Neuer Name';browser.groupList[0].color='green';browser.tabList[0].url='https://example.org/next';await projection.observe();
    assert.equal(workspace.live('space')[0].id,space.id);assert.equal(valueOf(workspace.get('space',space.id)).name,'Neuer Name');assert.equal(valueOf(workspace.get('space',space.id)).accent,'teal');assert.equal(workspace.live('tab')[0].id,tab.id);assert.equal(valueOf(workspace.get('tab',tab.id)).url,'https://example.org/next');
});
test('manual close creates a tombstone but window close preserves all shared records',async()=>{
    const a=await fixture(),id=a.workspace.live('tab')[0].id;await a.projection.removed(2,{isWindowClosing:false});assert.equal(a.workspace.get('tab',id).isTombstone,true);
    const b=await fixture(),kept=b.workspace.live('tab')[0].id;await b.projection.removed(2,{isWindowClosing:true});assert.equal(b.workspace.get('tab',kept).isTombstone,false);assert.equal(b.workspace.state.bindings.tabs[2],undefined);
});
test('empty/removed group never authorizes deleting the Space',async()=>{
    const {workspace,browser,projection}=await fixture(),space=workspace.live('space')[0];browser.groupList=[];browser.tabList=[];await projection.observe();assert.equal(workspace.get('space',space.id).isTombstone,false);assert.equal(workspace.live('tab').length,1);
});
test('tabs moving between groups keep identity and update Space ownership',async()=>{
    const {workspace,browser,projection}=await fixture(),id=workspace.live('tab')[0].id;browser.group('Privat',3);browser.tabList[0].groupId=3;await projection.observe();const destination=workspace.live('space').find(s=>valueOf(s).name==='Privat');assert.equal(workspace.get('tab',id).spaceID,destination.id);assert.equal(workspace.live('tab').length,1);
});
test('native order changes retain tab identities',async()=>{
    const {workspace,browser,projection}=await fixture();browser.tab('https://example.org/second',1,3);await projection.observe();const ids=workspace.live('tab').map(r=>r.id);browser.tabList.reverse();browser.tabList.forEach((tab,i)=>tab.index=i);await projection.observe();assert.deepEqual(workspace.live('tab').map(r=>r.id),ids.reverse());
});
test('restart rebinds unique restored groups and tabs without deletion or duplicates',async()=>{
    const {workspace,browser,projection}=await fixture(),before=structuredClone(workspace.state.records);browser.groupList[0].id=101;browser.tabList[0].id=102;browser.tabList[0].groupId=101;
    await projection.restoreBindings();assert.equal(Object.keys(workspace.state.bindings.tabs)[0],'102');await projection.observe();assert.equal(workspace.live('space').length,1);assert.equal(workspace.live('tab').length,1);assert.deepEqual(workspace.state.records,before);
});
test('loss of all native tab information after crash never stages a deletion',async()=>{
    const {workspace,browser,projection}=await fixture(),before=structuredClone(workspace.state.records);browser.groupList=[];browser.tabList=[];await projection.restoreBindings();await projection.observe();assert.deepEqual(workspace.state.records,before);
});
test('remote tab update and close are applied without echo tombstones',async()=>{
    const {workspace,browser,projection}=await fixture(),record=workspace.live('tab')[0];workspace.edit('tab',record.id,v=>{v.url='https://example.org/remote';});await projection.apply();assert.equal(browser.tabList[0].url,'https://example.org/remote');
    workspace.remove('tab',record.id);const clock=workspace.state.clock;await projection.apply();assert.deepEqual(browser.closed,[2]);await projection.removed(2,{isWindowClosing:false});assert.equal(workspace.state.clock,clock);
});
test('saved tabs are held without native pages; explicitly saving an open tab does not delete it',async()=>{
    const {workspace,browser,projection}=await fixture(),record=workspace.live('tab')[0];workspace.moveTab(record.id,record.spaceID,null,'saved');await projection.apply();await projection.removed(2,{isWindowClosing:false});assert.equal(workspace.get('tab',record.id).isTombstone,false);assert.equal(valueOf(workspace.get('tab',record.id)).placement,'saved');assert.equal(browser.tabList.length,0);
});
test('pinning keeps Space ownership even though Chromium ungrouped the tab',async()=>{
    const {workspace,browser,projection}=await fixture(),record=workspace.live('tab')[0];browser.tabList[0].pinned=true;browser.tabList[0].groupId=-1;await projection.observe();assert.equal(workspace.get('tab',record.id).spaceID,record.spaceID);assert.equal(valueOf(workspace.get('tab',record.id)).placement,'pinned');
});
test('incognito tabs/groups are excluded from adoption',async()=>{
    const workspace=new Workspace(),browser=new FakeBrowser();browser.group().incognito=true;browser.tab().incognito=true;const projection=new BrowserProjection(workspace,browser,async()=>{});await projection.observe({capture:true});assert.equal(workspace.live('space').length,0);assert.equal(workspace.live('tab').length,0);
});
test('more than ten remote closes are held until an explicit UI decision',async()=>{
    const {workspace,browser,projection}=await fixture(),space=workspace.live('space')[0];for(let i=0;i<11;i++)browser.tab(`https://example.org/${i}`,1,20+i);await projection.observe();for(const tab of workspace.live('tab'))workspace.remove('tab',tab.id);
    await projection.apply();assert.equal(browser.closed.length,0);assert.equal(workspace.state.deletionHold,12);await projection.apply({approveDeletions:true});assert.equal(browser.closed.length,12);
});
test('remote creation is projected once and retained records do not reopen after a window close',async()=>{
    const workspace=new Workspace(),browser=new FakeBrowser(),space=workspace.addSpace('Remote'),record=workspace.addTab(space.id,'https://example.org/','Test','current');const projection=new BrowserProjection(workspace,browser,async()=>{});
    await projection.apply();assert.equal(browser.tabList.length,1);await projection.apply();assert.equal(browser.tabList.length,1);const id=browser.tabList[0].id;browser.tabList=[];browser.groupList=[];await projection.removed(id,{isWindowClosing:true});await projection.apply();assert.equal(browser.tabList.length,0);assert.equal(workspace.get('tab',record.id).isTombstone,false);
});
test('no automatic window creation when every normal window is gone',async()=>{
    const workspace=new Workspace(),browser=new FakeBrowser(),space=workspace.addSpace('Remote');workspace.addTab(space.id,'https://example.org/','Test','current');browser.windowsList=[];await new BrowserProjection(workspace,browser,async()=>{}).apply();assert.equal(browser.tabList.length,0);
});
