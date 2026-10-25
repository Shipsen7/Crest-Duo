// SPDX-License-Identifier: MPL-2.0
import {Workspace} from './core/workspace.js';
import {BrowserProjection,groupColors} from './browser/projection.js';
import {CloudClient,CloudError} from './cloud/client.js';
import {AppleAuth} from './cloud/auth.js';
import {SyncEngine} from './core/sync.js';
import {valueOf,identity,text,now,uuid,webURL} from './core/record.js';
let tail=Promise.resolve();
const session={get:async()=> (await chrome.storage.session.get('auth')).auth,
    set:async auth=>chrome.storage.session.set({auth}),clear:async()=>chrome.storage.session.remove('auth')};
async function context() {
    await chrome.storage.local.setAccessLevel({accessLevel:'TRUSTED_CONTEXTS'});
    await chrome.storage.session.setAccessLevel({accessLevel:'TRUSTED_CONTEXTS'});
    if(!await chrome.alarms.get('poll'))await chrome.alarms.create('poll',{periodInMinutes:1});
    const stored=await chrome.storage.local.get('workspace');
    const workspace=new Workspace(stored.workspace);
    const save=()=>chrome.storage.local.set({workspace:workspace.state});
    const projection=new BrowserProjection(workspace,chrome,save);
    const live=(await chrome.storage.session.get('runtimeReady')).runtimeReady;
    if(!live) {
        await projection.restoreBindings();
        await chrome.storage.session.set({runtimeReady:true});
    }
    const client=new CloudClient(workspace.state.config,session);
    return {workspace,projection,save,client};
}
function enqueue(operation) {
    const run=async()=>{
        const ctx=await context();
        try {return await operation(ctx);}
        catch(error) {
            ctx.workspace.state.status=error instanceof CloudError?error.message:typeof error?.message==='string' && !/https?:|token|password|secret/i.test(error.message)?error.message:'Aktion fehlgeschlagen. Daten bleiben lokal erhalten.';
            await ctx.save();throw new Error(ctx.workspace.state.status);
        }
    };
    const result=tail.then(run,run);tail=result.catch(()=>{});return result;
}
async function scheduleSoon() {if(!await chrome.alarms.get('local-change'))await chrome.alarms.create('local-change',{delayInMinutes:0.5});}
async function observe(ctx) {const before=ctx.workspace.state.clock;await ctx.projection.observe();await scheduleSoon();if(before!==ctx.workspace.state.clock && Date.now()-(ctx.workspace.state.lastAttempt??0)>3000)await sync(ctx);}
async function sync(ctx) {
    const state=ctx.workspace.state;
    if(!state.config.apiToken || !(await session.get())?.token) {state.status='Nur lokal · Apple-Anmeldung erforderlich';await ctx.save();return;}
    if(state.nextRetry && Date.now()<state.nextRetry)return;
    state.lastAttempt=Date.now();await ctx.save();
    try {
        await new SyncEngine(ctx.workspace,ctx.client,ctx.save).run();
        state.failures=0;state.nextRetry=null;
        await ctx.projection.apply();await ctx.save();
    } catch(error) {
        state.failures=(state.failures??0)+1;
        const delay=Math.max(Number(error.retryAfter)||0,Math.min(1800,30*2**Math.min(state.failures-1,6)));
        state.nextRetry=Date.now()+delay*1000;
        await chrome.alarms.create('retry',{when:state.nextRetry});
        throw error;
    }
}
async function present(ctx) {
    const state=ctx.workspace.state;
    const clean=structuredClone(state);delete clean.config.apiToken;delete clean.account;delete clean.serverTags;delete clean.pending;
    clean.pendingCount=Object.keys(state.pending).length;clean.signedIn=Boolean((await session.get())?.token);
    clean.callback=chrome.identity.getRedirectURL('cloudkit');
    // The UI never receives bearer tokens or raw account identifiers.
    return clean;
}
const actions={
    state:present,
    capture:async ctx=>{await ctx.projection.observe({capture:true});await scheduleSoon();},
    sync:async ctx=>{ctx.workspace.state.nextRetry=null;await sync(ctx);},
    addSpace:async(ctx,message)=>{ctx.workspace.addSpace(message.name);await ctx.save();},
    rename:async(ctx,message)=>{
        if(!['space','folder','tab'].includes(message.kind))throw new Error('Ungültiger Eintrag.');
        ctx.workspace.edit(message.kind,message.id,value=>{
            if(message.kind==='space')value.name=text(message.name,128);
            else if(message.kind==='tab'){value.customTitle=text(message.name);value.titleModifiedAt=now();}
            else value.title=text(message.name,512);
        });await ctx.save();await ctx.projection.apply();
    },
    color:async(ctx,message)=>{
        if(!groupColors.includes(message.color))throw new Error('Ungültige Gruppenfarbe.');
        const accent={grey:'indigo',blue:'indigo',purple:'indigo',red:'rose',pink:'rose',yellow:'orange',orange:'orange',green:'teal',cyan:'teal'}[message.color];
        ctx.workspace.edit('space',message.id,value=>{value.accent=accent;});
        ctx.workspace.state.colors??={};ctx.workspace.state.colors[message.id]=message.color;await ctx.save();await ctx.projection.apply();
    },
    addFolder:async(ctx,message)=>{ctx.workspace.addFolder(message.spaceID,message.name,message.parentID||null,message.location??'saved');await ctx.save();},
    addTab:async(ctx,message)=>{ctx.workspace.addTab(message.spaceID,message.url,message.name,message.placement??'saved',message.folderID||null);await ctx.save();await ctx.projection.apply();},
    moveTab:async(ctx,message)=>{ctx.workspace.moveTab(message.id,message.spaceID,message.folderID||null,message.placement);await ctx.save();await ctx.projection.apply();},
    moveFolder:async(ctx,message)=>{ctx.workspace.moveFolder(message.id,message.parentID||null);await ctx.save();},
    reorder:async(ctx,message)=>{ctx.workspace.reorder(message.kind,message.ids,message.spaceID);await ctx.save();await ctx.projection.apply();},
    remove:async(ctx,message)=>{
        if(!['space','folder','tab'].includes(message.kind))throw new Error('Ungültiger Eintrag.');
        ctx.workspace.remove(message.kind,message.id);await ctx.save();await ctx.projection.apply({approveDeletions:true});
    },
    openSpace:async(ctx,message)=>{ctx.workspace.editable(message.id);await ctx.projection.apply({openSpace:message.id});},
    openTab:async(ctx,message)=>{
        const record=ctx.workspace.get('tab',message.id);if(!record || record.isTombstone)throw new Error('Tab fehlt.');ctx.workspace.editable(record.spaceID);
        const native=Object.entries(ctx.workspace.state.bindings.tabs).find(([,id])=>id===record.id)?.[0];
        if(native) {try {const tab=await chrome.tabs.get(Number(native));await chrome.tabs.update(tab.id,{active:true});await chrome.windows.update(tab.windowId,{focused:true});return;}catch{}}
        if(valueOf(record).placement==='saved') {
            // Open a local page without changing the saved record's durable placement.
            const url=webURL(valueOf(record).savedURL??valueOf(record).url);if(!url)throw new Error('Dieser Inhalt lässt sich hier nicht öffnen.');
            const tab=await chrome.tabs.create({url,active:true});ctx.workspace.state.bindings.tabs[tab.id]=record.id;await ctx.save();
        } else await ctx.projection.apply({openSpace:record.spaceID});
    },
    approveDeletions:async ctx=>ctx.projection.apply({approveDeletions:true}),
    configure:async(ctx,message)=>{
        const config=message.config??{},old=ctx.workspace.state.config;
        const candidate={container:String(config.container??''),environment:String(config.environment??''),zone:String(config.zone??''),
            apiToken:config.apiToken?String(config.apiToken):old.apiToken,writeEnabled:config.writeEnabled===true};
        if(candidate.container!=='iCloud.io.github.shipsen7.fennavio' || !['development','production'].includes(candidate.environment) || !/^[A-Za-z0-9-]{1,100}$/.test(candidate.zone) || candidate.apiToken.length>1000)
            throw new Error('Ungültige CloudKit-Konfiguration.');
        if(candidate.writeEnabled && (candidate.environment!=='development' || !candidate.zone.startsWith('CrestReview-')))throw new CloudError('WRITE_BLOCKED');
        const fingerprint=JSON.stringify([candidate.container,candidate.environment,candidate.zone]);
        if(ctx.workspace.state.cloudIdentity && ctx.workspace.state.cloudIdentity!==fingerprint)
            throw new Error('Dieser lokale Bestand gehört bereits zu einer anderen CloudKit-Umgebung. Für einen Wechsel ein getrenntes Browserprofil verwenden.');
        ctx.workspace.state.config=candidate;ctx.workspace.state.nextRetry=null;await session.clear();await ctx.save();
    },
    signIn:async ctx=>{
        const user=await new AppleAuth(ctx.client,chrome.identity,session).signIn();
        if(ctx.workspace.state.account && ctx.workspace.state.account!==user) {await session.clear();throw new CloudError('ACCOUNT_CHANGED');}
        ctx.workspace.state.account=user;ctx.workspace.state.cloudIdentity=JSON.stringify([ctx.workspace.state.config.container,ctx.workspace.state.config.environment,ctx.workspace.state.config.zone]);
        ctx.workspace.state.status='Angemeldet · Abgleich kann gestartet werden';await ctx.save();
    },
    signOut:async ctx=>{await session.clear();ctx.workspace.state.status='Abgemeldet · Bestand bleibt lokal';await ctx.save();}
};
chrome.runtime.onMessage.addListener((message,sender,respond)=>{
    if(sender.id!==chrome.runtime.id || !sender.url?.startsWith(chrome.runtime.getURL('ui/')) || !Object.hasOwn(actions,message?.action))return false;
    enqueue(async ctx=>{
        await actions[message.action](ctx,message);if(message.action!=='state'){await scheduleSoon();if(!['sync','signOut','configure','signIn'].includes(message.action))await sync(ctx);}return present(ctx);
    }).then(state=>respond({ok:true,state}),error=>respond({ok:false,error:error.message}));return true;
});
chrome.tabs.onRemoved.addListener((id,info)=>{enqueue(async ctx=>{await ctx.projection.removed(id,info);await scheduleSoon();}).catch(()=>{});});
for(const event of [chrome.tabs.onCreated,chrome.tabs.onUpdated,chrome.tabs.onMoved,chrome.tabs.onAttached,chrome.tabGroups.onCreated,chrome.tabGroups.onUpdated,chrome.tabGroups.onMoved,chrome.tabGroups.onRemoved])
    event.addListener(()=>enqueue(observe).catch(()=>{}));
chrome.tabs.onReplaced.addListener((added,removed)=>enqueue(async ctx=>{
    const bindings=ctx.workspace.state.bindings.tabs;if(bindings[removed]){bindings[added]=bindings[removed];delete bindings[removed];await ctx.save();}await observe(ctx);
}).catch(()=>{}));
chrome.runtime.onInstalled.addListener(()=>enqueue(async ctx=>{await ctx.save();await chrome.alarms.create('poll',{periodInMinutes:1});}).catch(()=>{}));
chrome.runtime.onStartup.addListener(()=>enqueue(async ctx=>{await chrome.alarms.create('poll',{periodInMinutes:1});await ctx.projection.restoreBindings();await sync(ctx);}).catch(()=>{}));
chrome.alarms.onAlarm.addListener(()=>enqueue(sync).catch(()=>{}));
