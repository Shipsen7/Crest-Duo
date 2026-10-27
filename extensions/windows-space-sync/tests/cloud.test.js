// SPDX-License-Identifier: MPL-2.0
import test from 'node:test';import assert from 'node:assert/strict';
import {CloudClient,CloudError} from '../extension/cloud/client.js';import {CloudCodec} from '../extension/cloud/codec.js';
import {AppleAuth,appleAuthURL,callbackToken} from '../extension/cloud/auth.js';import {SyncEngine} from '../extension/core/sync.js';
import {Workspace} from '../extension/core/workspace.js';import {keyOf,valueOf,mergeRecords} from '../extension/core/record.js';
const config={container:'iCloud.io.github.shipsen7.fennavio',environment:'development',zone:'CrestReview-test',apiToken:'not-a-real-token',writeEnabled:true};
function memorySession(){let value={token:'first'};return{get:async()=>value,set:async v=>{value=v;},clear:async()=>{value=null;}};}
const response=data=>({ok:true,headers:new Headers(),text:async()=>JSON.stringify(data)});
function records(){const w=new Workspace(),space=w.addSpace('A');w.addTab(space.id,'https://example.org/','A','current');return Object.values(w.state.records);}
test('paginated zone pull rotates auth token serially and preserves uint64 fields',async()=>{
    const sources=records();let calls=0;const client=new CloudClient(config,memorySession(),async(url,options)=>{
        const parsed=new URL(url),request=JSON.parse(options.body);assert.equal(parsed.hostname,'api.apple-cloudkit.com');
        assert.equal(parsed.searchParams.get('ckWebAuthToken'),calls?'rotated':'first');assert.equal(request.numberAsStrings,true);
        assert.equal(request.zones[0].syncToken,calls?'page1':undefined);const wire=CloudCodec.encode(sources[calls]);wire.recordChangeTag='tag'+calls;
        return response({ckWebAuthToken:'rotated',zones:[{zoneID:{zoneName:config.zone},records:[wire],syncToken:++calls===1?'page1':'page2',moreComing:calls===1}]});
    });const result=await client.pull();assert.equal(result.records.length,2);assert.equal(result.cursor,'page2');
});
test('production writes and non-review-zone writes are rejected before network',async()=>{
    for(const candidate of [{...config,environment:'production'},{...config,zone:'CrestPrivate'},{...config,writeEnabled:false}]){
        let called=false;const client=new CloudClient(candidate,memorySession(),async()=>{called=true;});await assert.rejects(()=>client.push(records()),e=>e.code==='WRITE_BLOCKED');assert.equal(called,false);
    }
});
test('push uses compare-and-swap update, never force writes or physical deletes',async()=>{
    const sent=records(),tags={[keyOf(sent[0])]:'old'};let request;
    const client=new CloudClient(config,memorySession(),async(url,options)=>{request=JSON.parse(options.body);return response({records:sent.map(record=>({...CloudCodec.encode(record),recordChangeTag:'new'}))});});
    const result=await client.push(sent,tags);assert.equal(request.atomic,true);assert.deepEqual(request.operations.map(o=>o.operationType),['update','create']);assert.equal(request.operations[0].record.recordChangeTag,'old');assert.equal(result.acknowledged.length,2);
});
test('conflict does not acknowledge the outbox',async()=>{
    const sent=records();const client=new CloudClient(config,memorySession(),async()=>response({records:sent.map(record=>({recordName:keyOf(record),serverErrorCode:'CONFLICT'}))}));
    await assert.rejects(()=>client.push(sent),e=>e instanceof CloudError && e.code==='CONFLICT');
});
test('auth callback and redirects are origin-bound',()=>{
    const expected='https://extensionid.chromiumapp.org/cloudkit';assert.equal(callbackToken(expected+'?ckWebAuthToken=a%2Bb',expected),'a+b');
    for(const url of ['https://evil.example/?ckWebAuthToken=x',expected+'/other?ckWebAuthToken=x',expected+'?ckWebAuthToken=a&ckWebAuthToken=b'])assert.throws(()=>callbackToken(url,expected));
    assert.equal(appleAuthURL('https://idmsa.apple.com/login'),'https://idmsa.apple.com/login');
    for(const url of ['https://apple.com.evil.example/','http://icloud.com/','https://user:pass@apple.com/'])assert.throws(()=>appleAuthURL(url));
});
test('failed Apple sign-in stores no session token',async()=>{
    const session=memorySession(),client={currentUser:async()=>{throw new CloudError('AUTHENTICATION_REQUIRED',0,'https://idmsa.apple.com/login');}};
    const auth=new AppleAuth(client,{getRedirectURL:()=> 'https://extensionid.chromiumapp.org/cloudkit',launchWebAuthFlow:async()=>{throw new Error();}},session);
    await assert.rejects(()=>auth.signIn());assert.equal(await session.get(),null);
});
test('authentication expiry clears old bearer token and error does not expose server payload',async()=>{
    const session=memorySession(),client=new CloudClient(config,session,async()=>response({serverErrorCode:'AUTHENTICATION_REQUIRED',reason:'PRIVATE URL AND TOKEN'}));
    await assert.rejects(()=>client.currentUser(),e=>!e.message.includes('PRIVATE'));assert.equal(await session.get(),null);
});
test('offline outbox survives failure and converges after reconnect between two devices',async()=>{
    const a=new Workspace(),space=a.addSpace('A'),tab=a.addTab(space.id,'https://example.org/','A','current');a.state.config=config;
    const server=new Map();let online=false,saves=0;
    const transport={currentUser:async()=> 'account',pull:async()=>{if(!online)throw new CloudError();return{records:[...server.values()],cursor:'cursor',tags:{}};},push:async records=>{for(const r of records)server.set(keyOf(r),mergeRecords(server.get(keyOf(r)),r));return{acknowledged:records,tags:{}};}};
    const engine=new SyncEngine(a,transport,async()=>{saves++;});await assert.rejects(()=>engine.run());assert.equal(Object.keys(a.state.pending).length,2);
    online=true;await engine.run();assert.equal(Object.keys(a.state.pending).length,0);
    const b=new Workspace();b.state.config=config;await new SyncEngine(b,transport,async()=>{}).run();b.edit('tab',tab.id,v=>{v.customTitle='Apple';v.titleModifiedAt=100;});await new SyncEngine(b,transport,async()=>{}).run();await engine.run();
    assert.equal(valueOf(a.get('tab',tab.id)).customTitle,'Apple');a.remove('tab',tab.id);await engine.run();await new SyncEngine(b,transport,async()=>{}).run();assert.equal(b.get('tab',tab.id).isTombstone,true);assert.ok(saves>0);
});
test('save failure stops upload and cursor never outruns accepted data',async()=>{
    const workspace=new Workspace(),remote=records();let pushed=false;
    const transport={currentUser:async()=> 'account',pull:async()=>({records:remote,cursor:'new',tags:{}}),push:async()=>{pushed=true;}};
    await assert.rejects(()=>new SyncEngine(workspace,transport,async()=>{throw new Error('disk full');}).run());assert.equal(pushed,false);
});
test('account change blocks both pull and upload',async()=>{
    const workspace=new Workspace();workspace.state.account='old';let pulled=false;
    const transport={currentUser:async()=> 'different',pull:async()=>{pulled=true;}};await assert.rejects(()=>new SyncEngine(workspace,transport,async()=>{}).run(),e=>e.code==='ACCOUNT_CHANGED');assert.equal(pulled,false);
});
test('expired cursor refetches without interpreting absent records as deletions',async()=>{
    const workspace=new Workspace(),space=workspace.addSpace('Keep');workspace.state.cursor='expired';let calls=0;
    const transport={currentUser:async()=> 'account',pull:async cursor=>{if(++calls===1)throw new CloudError('CHANGE_TOKEN_EXPIRED');assert.equal(cursor,null);return{records:[],cursor:'fresh',tags:{}};}};
    await new SyncEngine(workspace,transport,async()=>{}).run();assert.equal(workspace.get('space',space.id).isTombstone,false);assert.equal(workspace.state.cursor,'fresh');
});
