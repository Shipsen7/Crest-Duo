// SPDX-License-Identifier: MPL-2.0
import {valueOf,identity,wrapped,now,text,webURL,keyOf,uuid} from '../core/record.js';
export const groupColors=['grey','blue','red','yellow','green','pink','purple','cyan','orange'];
const accents={grey:'indigo',blue:'indigo',purple:'indigo',red:'rose',pink:'rose',yellow:'orange',orange:'orange',green:'teal',cyan:'teal'};
export class BrowserProjection {
    constructor(workspace,browser,save) {this.workspace=workspace;this.browser=browser;this.save=save;}
    color(space) {return this.workspace.state.colors?.[space.id] ?? ({indigo:'blue',orange:'orange',teal:'cyan',rose:'pink'})[valueOf(space).accent] ?? 'grey';}
    allowed(record) {
        const space=record && this.workspace.get('space',record.spaceID);
        return record && space && !space.isTombstone && (valueOf(space).accessPolicy??'open')==='open' && !valueOf(record)?.nativeContent;
    }
    async snapshot() {
        const tabs=(await this.browser.tabs.query({})).filter(tab=>!tab.incognito);
        const groups=(await this.browser.tabGroups.query({})).filter(group=>!group.incognito);
        return {tabs,groups};
    }
    async restoreBindings() {
        const {tabs,groups}=await this.snapshot(),state=this.workspace.state;
        state.bindings={tabs:{},groups:{}};state.suppressed={};
        // Only exact, unique name+color matches are rebound. Absence never deletes a record.
        for(const group of groups) {
            const candidates=this.workspace.live('space').filter(space=>this.allowed(space) && valueOf(space).name===(group.title||'Ohne Titel') && this.color(space)===group.color);
            const duplicateGroups=groups.filter(other=>other.title===group.title && other.color===group.color);
            if(candidates.length!==1 || duplicateGroups.length!==1)continue;
            const space=candidates[0];state.bindings.groups[group.id]=space.id;
            const native=tabs.filter(tab=>tab.groupId===group.id);
            for(const tab of native) {
                const matches=this.workspace.live('tab',space.id).filter(record=>valueOf(record).placement!=='saved' && webURL(valueOf(record).url)===webURL(tab.url));
                if(matches.length===1 && native.filter(other=>webURL(other.url)===webURL(tab.url)).length===1)state.bindings.tabs[tab.id]=matches[0].id;
            }
        }
        // Chromium pins cannot belong to a tab group. Bind only an unambiguous global pin.
        for(const tab of tabs.filter(tab=>tab.pinned)) {
            const matches=this.workspace.live('tab').filter(record=>this.allowed(record) && valueOf(record).placement==='pinned' && webURL(valueOf(record).url)===webURL(tab.url));
            if(matches.length===1 && tabs.filter(other=>other.pinned && webURL(other.url)===webURL(tab.url)).length===1)state.bindings.tabs[tab.id]=matches[0].id;
        }
        await this.save();
    }
    async observe({capture=false}={}) {
        const {tabs,groups}=await this.snapshot(),state=this.workspace.state;
        if(capture)state.capture=true;
        if(!state.capture)return;
        state.colors??={};
        for(const group of groups) {
            let spaceID=state.bindings.groups[group.id];
            if(!spaceID) {
                const candidates=this.workspace.live('space').filter(space=>valueOf(space).name===(group.title||'Ohne Titel') && this.color(space)===group.color);
                const memberOwners=new Set(tabs.filter(tab=>tab.groupId===group.id).map(tab=>this.workspace.get('tab',state.bindings.tabs[tab.id])?.spaceID).filter(Boolean));
                if(candidates.length===1 && memberOwners.size===1 && memberOwners.has(candidates[0].id) && !groups.some(other=>other.id!==group.id && state.bindings.groups[other.id]===candidates[0].id)) {spaceID=candidates[0].id;state.bindings.groups[group.id]=spaceID;}
            }
            if(!spaceID) {
                // A restored group with ambiguous identity needs explicit adoption, avoiding duplicate Spaces.
                if(!capture && this.workspace.live('space').some(space=>valueOf(space).name===(group.title||'Ohne Titel')))continue;
                const space=this.workspace.addSpace(group.title||'Ohne Titel',accents[group.color]??'indigo');
                spaceID=space.id;state.bindings.groups[group.id]=spaceID;
            }
            const space=this.workspace.get('space',spaceID);
            if(!space || space.isTombstone || !this.allowed(space))continue;
            if(valueOf(space).name!==(group.title||'Ohne Titel') || state.colors[spaceID]!==group.color) {
                this.workspace.edit('space',spaceID,value=>{value.name=text(group.title||'Ohne Titel',128);value.accent=accents[group.color]??'indigo';});
                state.colors[spaceID]=group.color;
            }
        }
        for(const tab of tabs) {
            const url=webURL(tab.url);if(!url)continue;
            let id=state.bindings.tabs[tab.id],record=id?this.workspace.get('tab',id):null;
            const groupSpace=state.bindings.groups[tab.groupId];
            if(!id && groupSpace && this.allowed(this.workspace.get('space',groupSpace))) {
                // Once a Space has been restored, uniquely match its existing URL before creating anything.
                const bound=new Set(Object.values(state.bindings.tabs));
                const candidates=this.workspace.live('tab',groupSpace).filter(r=>!bound.has(r.id) && valueOf(r).placement!=='saved' && valueOf(r).url===url);
                if(candidates.length===1)record=candidates[0];
                else record=this.workspace.addTab(groupSpace,url,tab.title,'current');
                id=record.id;state.bindings.tabs[tab.id]=id;
            }
            if(!record || record.isTombstone || !this.allowed(record))continue;
            const value=valueOf(record),placement=tab.pinned?'pinned':value.placement==='saved'?'saved':'current';
            const destination=groupSpace??record.spaceID;
            if(destination!==record.spaceID || placement!==value.placement) this.workspace.moveTab(id,destination,null,placement);
            const current=valueOf(this.workspace.get('tab',id));
            if(current.url!==url || current.title!==text(tab.title||new URL(url).hostname))this.workspace.edit('tab',id,value=>{value.url=url;value.title=text(tab.title||new URL(url).hostname);});
            state.projection[id]=JSON.stringify(this.workspace.get('tab',id));
        }
        // A group's visible order is a flat projection; retain folders while updating relative tab positions.
        for(const group of groups) {
            const ids=tabs.filter(tab=>tab.groupId===group.id && state.bindings.tabs[tab.id] && !this.workspace.get('tab',state.bindings.tabs[tab.id])?.isTombstone).sort((a,b)=>a.index-b.index).map(tab=>state.bindings.tabs[tab.id]);
            if(ids.length) this.workspace.reorder('tab',ids,state.bindings.groups[group.id]);
        }
        for(const windowID of new Set(groups.map(group=>group.windowId))) {
            const ordered=groups.filter(group=>group.windowId===windowID && state.bindings.groups[group.id]).sort((a,b)=>
                Math.min(...tabs.filter(tab=>tab.groupId===a.id).map(tab=>tab.index))-Math.min(...tabs.filter(tab=>tab.groupId===b.id).map(tab=>tab.index)));
            const spaceIDs=[...new Set(ordered.map(group=>state.bindings.groups[group.id]))];
            if(spaceIDs.length)this.workspace.reorder('space',spaceIDs);
        }
        for(const space of this.workspace.live('space')) {
            const ids=tabs.filter(tab=>tab.pinned && state.bindings.tabs[tab.id] && this.workspace.get('tab',state.bindings.tabs[tab.id])?.spaceID===space.id && !this.workspace.get('tab',state.bindings.tabs[tab.id])?.isTombstone)
                .sort((a,b)=>a.index-b.index).map(tab=>state.bindings.tabs[tab.id]);
            if(ids.length)this.workspace.reorder('tab',ids,space.id);
        }
        // Group removal is deliberately not a Space deletion.
        const existingGroups=new Set(groups.map(group=>String(group.id)));
        for(const id of Object.keys(state.bindings.groups))if(!existingGroups.has(id))delete state.bindings.groups[id];
        await this.save();
    }
    async removed(tabID,info) {
        const state=this.workspace.state,id=state.bindings.tabs[tabID];
        if(!id)return;
        const suppressed=state.suppressed?.[tabID];
        if(suppressed)delete state.suppressed[tabID];
        const record=this.workspace.get('tab',id);
        delete state.bindings.tabs[tabID];
        if(!suppressed && !info.isWindowClosing && record && !record.isTombstone && valueOf(record).placement!=='saved' && this.allowed(record))this.workspace.remove('tab',id);
        if(record)state.projection[id]=JSON.stringify(this.workspace.get('tab',id));
        await this.save();
    }
    async closeNative(tabID) {
        const state=this.workspace.state;state.suppressed??={};state.suppressed[tabID]=true;
        await this.save();
        try {await this.browser.tabs.remove(Number(tabID));}
        catch {delete state.suppressed[tabID];delete state.bindings.tabs[tabID];await this.save();}
    }
    async apply({openSpace=null,approvalToken=null,approvedIDs=[]}={}) {
        const state=this.workspace.state,{tabs,groups}=await this.snapshot();
        const nativeByID=new Map(tabs.map(tab=>[String(tab.id),tab]));
        const closes=Object.entries(state.bindings.tabs).filter(([tabID,id])=>nativeByID.has(tabID) &&
            (this.workspace.get('tab',id)?.isTombstone || this.workspace.get('space',this.workspace.get('tab',id)?.spaceID)?.isTombstone));
        const unapproved=closes.filter(([,id])=>!approvedIDs.includes(id));
        const signature=JSON.stringify(unapproved.map(([,id])=>[id,this.workspace.get('tab',id)?.version,this.workspace.get('space',this.workspace.get('tab',id)?.spaceID)?.version]));
        const validApproval=approvalToken && approvalToken===state.deletionReview?.token && signature===state.deletionReview?.signature;
        if(unapproved.length>10 && !validApproval) {
            if(state.deletionReview?.signature!==signature)state.deletionReview={signature,token:uuid(),names:unapproved.map(([,id])=>{
                try{return valueOf(JSON.parse(state.projection[id]))?.title??id;}catch{return id;}
            })};
            state.deletionHold=unapproved.length;state.status=`${unapproved.length} entfernte Tabs warten auf Prüfung im Popup.`;await this.save();return;
        }
        delete state.deletionHold;delete state.deletionReview;
        for(const [tabID] of closes)await this.closeNative(tabID);
        const windows=await this.browser.windows.getAll({windowTypes:['normal']});
        const targetWindow=windows.find(window=>!window.incognito)?.id;
        if(targetWindow===undefined)return; // Never create a window automatically.
        for(const space of this.workspace.live('space')) {
            if(!this.allowed(space))continue;
            let groupID=Object.entries(state.bindings.groups).find(([native,id])=>id===space.id && groups.some(group=>String(group.id)===native))?.[0];
            for(const record of this.workspace.live('tab',space.id)) {
                const value=valueOf(record);if(!this.allowed(record))continue;
                let tabID=Object.entries(state.bindings.tabs).find(([native,id])=>id===record.id && nativeByID.has(native))?.[0];
                if(value.placement==='saved') {
                    if(tabID)await this.closeNative(tabID);
                    state.projection[record.id]=JSON.stringify(record);continue;
                }
                if(!webURL(value.url))continue;
                const changed=state.projection[record.id]!==JSON.stringify(record);
                if(!tabID && (changed || openSpace===space.id)) {
                    const tab=await this.browser.tabs.create({url:value.url,active:false,windowId:groupID?groups.find(group=>group.id===Number(groupID))?.windowId??targetWindow:targetWindow,pinned:value.placement==='pinned'});
                    tabID=String(tab.id);state.bindings.tabs[tabID]=record.id;await this.save();
                }
                if(!tabID)continue;
                const current=await this.browser.tabs.get(Number(tabID));
                const update={};if(webURL(current.url)!==webURL(value.url))update.url=value.url;
                if(current.pinned!==(value.placement==='pinned'))update.pinned=value.placement==='pinned';
                if(Object.keys(update).length)await this.browser.tabs.update(Number(tabID),update);
                if(value.placement==='current') {
                    if(!groupID) {
                        groupID=String(await this.browser.tabs.group({tabIds:[Number(tabID)]}));state.bindings.groups[groupID]=space.id;
                        groups.push(await this.browser.tabGroups.get(Number(groupID)));await this.save();
                    } else if(current.groupId!==Number(groupID)) {
                        const group=await this.browser.tabGroups.get(Number(groupID));
                        if(current.windowId!==group.windowId)await this.browser.tabs.move(Number(tabID),{windowId:group.windowId,index:-1});
                        await this.browser.tabs.group({tabIds:[Number(tabID)],groupId:Number(groupID)});
                    }
                }
                state.projection[record.id]=JSON.stringify(record);
            }
            if(groupID) {
                const actualGroup=await this.browser.tabGroups.get(Number(groupID));
                if(actualGroup.title!==valueOf(space).name || actualGroup.color!==this.color(space))
                    await this.browser.tabGroups.update(Number(groupID),{title:valueOf(space).name,color:this.color(space)});
                state.colors??={};state.colors[space.id]=this.color(space);
                const ordered=this.workspace.live('tab',space.id).filter(record=>valueOf(record).placement==='current')
                    .map(record=>Object.entries(state.bindings.tabs).find(([,id])=>id===record.id)?.[0]).filter(Boolean).map(Number);
                const actualTabs=(await this.browser.tabs.query({groupId:Number(groupID)})).sort((a,b)=>a.index-b.index);
                const start=actualTabs[0]?.index;
                if(start!==undefined && ordered.some((id,index)=>actualTabs[index]?.id!==id)) {
                    // Reorder within the group's bounds; moving to the end of the window can ungroup a tab.
                    for(let index=0;index<ordered.length;index++)await this.browser.tabs.move(ordered[index],{index:start+index});
                    await this.browser.tabs.group({tabIds:ordered,groupId:Number(groupID)});
                }
            }
        }
        const finalTabs=(await this.browser.tabs.query({})).filter(tab=>!tab.incognito);
        const spaceOrder=new Map(this.workspace.live('space').map((space,index)=>[space.id,index]));
        for(const windowID of new Set(finalTabs.map(tab=>tab.windowId))) {
            const nativeGroups=(await this.browser.tabGroups.query({windowId:windowID})).filter(group=>state.bindings.groups[group.id] && this.allowed(this.workspace.get('space',state.bindings.groups[group.id])));
            const actual=nativeGroups.sort((a,b)=>Math.min(...finalTabs.filter(tab=>tab.groupId===a.id).map(tab=>tab.index))-Math.min(...finalTabs.filter(tab=>tab.groupId===b.id).map(tab=>tab.index)));
            const desired=[...actual].sort((a,b)=>spaceOrder.get(state.bindings.groups[a.id])-spaceOrder.get(state.bindings.groups[b.id]));
            if(desired.some((group,index)=>actual[index].id!==group.id))for(const group of desired)await this.browser.tabGroups.move(group.id,{index:-1});
            const nativePins=finalTabs.filter(tab=>tab.windowId===windowID && tab.pinned && state.bindings.tabs[tab.id]).sort((a,b)=>a.index-b.index);
            const pinOrder=this.workspace.live('space').flatMap(space=>this.workspace.live('tab',space.id).filter(record=>valueOf(record).placement==='pinned').map(record=>record.id));
            const wanted=[...nativePins].sort((a,b)=>pinOrder.indexOf(state.bindings.tabs[a.id])-pinOrder.indexOf(state.bindings.tabs[b.id]));
            if(wanted.some((tab,index)=>nativePins[index].id!==tab.id))for(let index=0;index<wanted.length;index++)await this.browser.tabs.move(wanted[index].id,{index:nativePins[index].index});
        }
        await this.save();
    }
}
