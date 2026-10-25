// SPDX-License-Identifier: MPL-2.0
import test from 'node:test';
import assert from 'node:assert/strict';
import {Workspace} from '../extension/core/workspace.js';
import {allocateOrder} from '../extension/core/order.js';
import {valueOf,mergeRecords,validateRecord,uuid,wrapped,compareVersion,webURL,sameRecord} from '../extension/core/record.js';
import {CloudCodec} from '../extension/cloud/codec.js';
function setup(){const workspace=new Workspace();const space=workspace.addSpace('Arbeit');const tab=workspace.addTab(space.id,'https://example.org/','Beispiel','current');return{workspace,space,tab};}
test('cloud body uses existing wrapped identities, Unix seconds and schema 1–3',()=>{
    const {workspace,space,tab}=setup();const folder=workspace.addFolder(space.id,'Offen',null,'current');
    const moved=workspace.moveTab(tab.id,space.id,folder.id,'current');assert.equal(moved.schema,2);
    const wire=CloudCodec.encode(moved,'tag-a');assert.equal(wire.recordName,`tab:${tab.id}`);assert.equal(wire.recordType,'CrestTab');
    assert.equal(wire.fields.payload.isEncrypted,true);assert.equal(wire.fields.space.value.recordName,`space:${space.id}`);
    const body=JSON.parse(Buffer.from(wire.fields.payload.value,'base64').toString());assert.equal(body.type,'tab');assert.equal(body.value.spaceID.rawValue,space.id);
    assert.ok(body.value.lastActivatedAt>1700000000);assert.deepEqual(CloudCodec.decode(wire),moved);
});
test('unknown body fields survive decode/edit/encode',()=>{
    const {workspace,tab}=setup();workspace.state.records[`tab:${tab.id}`].body.future={safe:'kept'};
    valueOf(workspace.get('tab',tab.id)).futureField={nested:23};workspace.edit('tab',tab.id,value=>{value.title='Neu';});
    const result=CloudCodec.decode(CloudCodec.encode(workspace.get('tab',tab.id)));assert.deepEqual(result.body.future,{safe:'kept'});assert.deepEqual(valueOf(result).futureField,{nested:23});
});
test('future schemas, mismatched identities and unencrypted fields fail closed',()=>{
    const {tab}=setup();assert.throws(()=>validateRecord({...tab,schema:4}));
    assert.throws(()=>validateRecord({...tab,id:uuid()}));
    const wire=CloudCodec.encode(tab);delete wire.fields.payload.isEncrypted;assert.throws(()=>CloudCodec.decode(wire));
});
test('uint64 versions are lossless above JavaScript safe integer',()=>{
    const a={clock:'9007199254740993',deviceID:uuid()},b={clock:'9007199254740992',deviceID:uuid()};assert.equal(compareVersion(a,b),1);
    const {tab}=setup();tab.version=a;assert.equal(CloudCodec.decode(CloudCodec.encode(tab)).version.clock,a.clock);
    assert.throws(()=>validateRecord({...tab,version:{...a,clock:'18446744073709551616'}}));
});
test('explicit deletion wins over offline edits and remains idempotent',()=>{
    const {workspace,tab}=setup();workspace.remove('tab',tab.id);const deleted=workspace.get('tab',tab.id);
    const edited=structuredClone(tab);edited.version.clock='999';valueOf(edited).lastActivatedAt=Date.now()/1000+100;
    assert.equal(mergeRecords(deleted,edited).isTombstone,true);assert.equal(mergeRecords(edited,deleted).isTombstone,true);assert.deepEqual(mergeRecords(deleted,deleted),deleted);
});
test('non-explicit cleanup loses to a later activated tab',()=>{
    const {tab}=setup();const deleted={...tab,body:{reason:'retention',deletedAt:1},isTombstone:true};
    assert.equal(mergeRecords(deleted,tab).isTombstone,false);
});
test('concurrent tab rename and relocation merge field clocks',()=>{
    const {tab}=setup(),a=structuredClone(tab),b=structuredClone(tab),folderID=uuid();
    valueOf(a).customTitle='Umbenannt';valueOf(a).titleModifiedAt=Date.now()/1000+10;a.version.clock='50';
    valueOf(b).folderID=wrapped(folderID);valueOf(b).positionModifiedAt=Date.now()/1000+20;b.schema=2;b.version.clock='51';
    const ab=mergeRecords(a,b),ba=mergeRecords(b,a);assert.deepEqual(ab,ba);assert.equal(valueOf(ab).customTitle,'Umbenannt');assert.equal(valueOf(ab).folderID.rawValue,folderID);
});
test('a more durable placement wins a position tie',()=>{
    const {tab}=setup(),saved=structuredClone(tab);valueOf(saved).placement='saved';assert.equal(valueOf(mergeRecords(tab,saved)).placement,'saved');
});
test('folder hierarchy rejects cycles and deletion preserves contents',()=>{
    const {workspace,space,tab}=setup();const parent=workspace.addFolder(space.id,'A'),child=workspace.addFolder(space.id,'B',parent.id);
    assert.throws(()=>workspace.moveFolder(parent.id,child.id));workspace.moveTab(tab.id,space.id,parent.id,'saved');workspace.remove('folder',parent.id);
    assert.equal(workspace.get('folder',parent.id).isTombstone,true);assert.equal(valueOf(workspace.get('tab',tab.id)).folderID,undefined);assert.equal(valueOf(workspace.get('folder',child.id)).parentID,undefined);
});
test('cross-Space tab moves retain identity, folder ownership is enforced',()=>{
    const {workspace,space,tab}=setup(),other=workspace.addSpace('Privat'),folder=workspace.addFolder(space.id,'A');
    assert.throws(()=>workspace.moveTab(tab.id,other.id,folder.id,'saved'));workspace.moveTab(tab.id,other.id,null,'saved');assert.equal(workspace.get('tab',tab.id).spaceID,other.id);assert.equal(workspace.get('tab',tab.id).id,tab.id);
});
test('Space deletion stages explicit child tombstones without physical deletion',()=>{
    const {workspace,space,tab}=setup();workspace.addFolder(space.id,'A');workspace.remove('space',space.id);
    assert.equal(workspace.get('tab',tab.id).isTombstone,true);assert.ok(Object.values(workspace.state.pending).every(record=>record.isTombstone));
});
test('locked Spaces cannot be changed or adopted',()=>{
    const {workspace,space}=setup();valueOf(workspace.get('space',space.id)).accessPolicy='locked';assert.throws(()=>workspace.addFolder(space.id,'A'));assert.throws(()=>workspace.remove('space',space.id));
});
test('portable URLs exclude credentials, script and local extension protocols',()=>{
    for(const url of ['javascript:alert(1)','file:///secret','chrome://settings','https://user:password@example.org/','data:text/plain,test'])assert.equal(webURL(url),null);
    assert.equal(webURL('https://example.org/a?b=1#c'),'https://example.org/a?b=1#c');
});
test('order allocation preserves anchors and handles arbitrary reorder',()=>{
    const tokens=allocateOrder([null,null,null,null]);assert.equal(new Set(tokens).size,4);assert.deepEqual(allocateOrder(tokens),tokens);
    const moved=allocateOrder([tokens[3],tokens[0],tokens[1],tokens[2]]);assert.equal(moved[1],tokens[0]);assert.equal(moved[2],tokens[1]);assert.ok(moved.every((t,i)=>!i||t>moved[i-1]));
    assert.deepEqual(allocateOrder(['0000000000000000',null]),['0000000000000000','7fffffffffffffff']);
});
test('partial malformed pull does not advance cursor or mutate records',()=>{
    const {workspace,tab}=setup(),before=structuredClone(workspace.state);assert.throws(()=>workspace.merge([tab,{...tab,id:'bad'}],'next'));
    assert.deepEqual(workspace.state,before);
});
test('acknowledgement cannot discard a newer local edit',()=>{
    const {workspace,tab}=setup();workspace.edit('tab',tab.id,v=>{v.title='Neu';});workspace.acknowledge([tab]);assert.ok(workspace.state.pending[`tab:${tab.id}`]);
});

test('cross-Space conflicts keep the winning record whole without foreign folder membership',()=>{
    const {tab}=setup(),other=structuredClone(tab);other.spaceID=uuid();valueOf(other).spaceID=wrapped(other.spaceID);other.version.clock='900';valueOf(tab).folderID=wrapped(uuid());valueOf(tab).positionModifiedAt=Date.now()/1000+100;tab.schema=2;
    const merged=mergeRecords(tab,other);assert.equal(merged.spaceID,other.spaceID);assert.equal(valueOf(merged).folderID,undefined);
});
test('semantic record equality prevents an upload loop after sorted CloudKit JSON',()=>{
    const {tab}=setup(),wire=CloudCodec.decode(CloudCodec.encode(tab));assert.equal(sameRecord(wire,tab),true);
    valueOf(wire).id.rawValue=tab.id.toUpperCase();valueOf(wire).folderID=null;assert.equal(sameRecord(wire,tab),true);
});

test('a later merge identity failure leaves the entire page and cursor uncommitted',()=>{
    const {workspace,space,tab}=setup(),other=workspace.addSpace('B'),folder=workspace.addFolder(space.id,'F');
    const changed=structuredClone(tab);changed.version.clock='100';valueOf(changed).title='Changed';
    const conflicting=structuredClone(folder);conflicting.spaceID=other.id;valueOf(conflicting).spaceID=wrapped(other.id);
    const before=structuredClone(workspace.state);assert.throws(()=>workspace.merge([changed,conflicting],'bad-page'));assert.deepEqual(workspace.state,before);
});
test('an explicit remote Space deletion also retires offline-created child records',()=>{
    const {workspace,space,tab}=setup(),deleted=structuredClone(space);deleted.isTombstone=true;deleted.body={reason:'explicitDelete',deletedAt:Date.now()/1000};deleted.version.clock='100';
    workspace.merge([deleted],'deleted-parent');assert.equal(workspace.get('tab',tab.id).isTombstone,true);assert.equal(workspace.state.pending[`tab:${tab.id}`].body.reason,'explicitDelete');
});
