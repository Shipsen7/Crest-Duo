// SPDX-License-Identifier: MPL-2.0
import {uuid,wrapped,identity,keyOf,valueOf,now,text,webURL,validateRecord,makeRecord,mergeRecords,sameRecord} from './record.js';
import {allocateOrder} from './order.js';
export class Workspace {
    constructor(state) {
        this.state = state ?? {format:1,deviceID:uuid(),clock:'0',records:{},pending:{},cursor:null,serverTags:{},
            bindings:{tabs:{},groups:{}},projection:{},capture:false,status:'Nur lokal · CloudKit nicht verbunden',
            config:{container:'iCloud.io.github.shipsen7.fennavio',environment:'development',zone:'CrestReview-WindowsSync',apiToken:'',writeEnabled:false},
            account:null,cloudIdentity:null,lastSync:null};
        if (this.state.format !== 1) throw new Error('Unbekanntes lokales Format; keine Daten wurden verändert.');
    }
    version() {
        const next=BigInt(this.state.clock)+1n;
        if (next>18446744073709551615n) throw new Error('Versionszähler erschöpft.');
        this.state.clock=String(next);
        return {clock:this.state.clock,deviceID:this.state.deviceID};
    }
    live(kind,spaceID) {
        return Object.values(this.state.records).filter(record => record.kind===kind && !record.isTombstone && (!spaceID || record.spaceID===spaceID))
            .sort((a,b) => (valueOf(a).orderToken < valueOf(b).orderToken ? -1 : valueOf(a).orderToken > valueOf(b).orderToken ? 1 : a.id.localeCompare(b.id)));
    }
    get(kind,id) { return this.state.records[`${kind}:${id}`]; }
    editable(spaceID) {
        const space=this.get('space',spaceID);
        if (!space || space.isTombstone || (valueOf(space).accessPolicy ?? 'open') !== 'open') throw new Error('Space fehlt oder ist geschützt.');
        return space;
    }
    put(record) {
        record=validateRecord(record); const key=keyOf(record);
        this.state.records[key]=record;
        this.state.pending[key]=structuredClone(record);
        return record;
    }
    create(kind,spaceID,value,id=uuid()) {
        if (kind!=='space') this.editable(spaceID);
        return this.put(makeRecord(kind,id,kind==='space'?id:spaceID,{...value,id:wrapped(id),...(kind!=='space'?{spaceID:wrapped(spaceID)}:{})},this.version()));
    }
    edit(kind,id,mutate) {
        const existing=this.get(kind,id);
        if (!existing || existing.isTombstone) throw new Error('Eintrag ist nicht mehr vorhanden.');
        this.editable(existing.spaceID);
        const value=structuredClone(valueOf(existing)); mutate(value);
        const record=structuredClone(existing); record.body.value=value; record.version=this.version();
        if (kind==='tab') { record.spaceID=identity(value.spaceID); this.editable(record.spaceID); record.schema=Math.max(record.schema,value.placement==='current' && value.folderID?2:1); }
        return this.put(record);
    }
    appendOrder(kind,spaceID) { return allocateOrder([...this.live(kind,spaceID).map(record=>valueOf(record).orderToken),null]).at(-1); }
    addSpace(name='Neuer Space',accent='indigo') {
        return this.create('space',null,{profileID:uuid(),name:text(name,128),symbol:'globe',accent,
            accessPolicy:'open',isSavedTabsExpanded:true,orderToken:this.appendOrder('space')});
    }
    addFolder(spaceID,title,parentID=null,location='saved') {
        if (parentID) {
            const parent=this.get('folder',parentID);
            if (!parent || parent.isTombstone || parent.spaceID!==spaceID || (valueOf(parent).location??'saved')!==location) throw new Error('Ungültiger Zielordner.');
        }
        return this.create('folder',spaceID,{title:text(title,512),location,...(parentID?{parentID:wrapped(parentID)}:{}),
            color:{red:0.4,green:0.45,blue:0.5,alpha:1},isCollapsed:false,orderToken:this.appendOrder('folder',spaceID)});
    }
    addTab(spaceID,url,title,placement='saved',folderID=null) {
        if (placement==='pinned' && this.live('tab',spaceID).filter(r=>valueOf(r).placement==='pinned').length>=12) throw new Error('Fennavio erlaubt höchstens 12 angeheftete Tabs pro Space.');
        url=webURL(url); if (!url) throw new Error('Nur HTTP(S)-Adressen ohne eingebettete Zugangsdaten sind erlaubt.');
        if (folderID) this.requireFolder(folderID,spaceID,placement);
        return this.create('tab',spaceID,{title:text(title||new URL(url).hostname),url,...(placement!=='current'?{savedURL:url}:{}),
            symbol:'globe',placement,...(folderID?{folderID:wrapped(folderID)}:{}),lastActivatedAt:now(),positionModifiedAt:now(),
            keepsPageLoaded:false,orderToken:this.appendOrder('tab',spaceID)});
    }
    requireFolder(id,spaceID,placement) {
        const folder=this.get('folder',id);
        if (!folder || folder.isTombstone || folder.spaceID!==spaceID || (valueOf(folder).location??'saved')!==placement) throw new Error('Ordner und Tab-Bereich passen nicht zusammen.');
    }
    moveTab(id,spaceID,folderID=null,placement='current') {
        this.editable(spaceID); if (folderID) this.requireFolder(folderID,spaceID,placement);
        if (placement==='pinned' && this.live('tab',spaceID).filter(r=>valueOf(r).placement==='pinned' && r.id!==id).length>=12)
            throw new Error('Fennavio erlaubt höchstens 12 angeheftete Tabs pro Space.');
        return this.edit('tab',id,value=>{
            value.spaceID=wrapped(spaceID); value.placement=placement; value.positionModifiedAt=now();
            value.orderToken=this.appendOrder('tab',spaceID); delete value.splitGroupID;
            if (folderID) value.folderID=wrapped(folderID); else delete value.folderID;
            if (placement!=='current') value.savedURL ??= value.url;
        });
    }
    moveFolder(id,parentID=null) {
        const record=this.get('folder',id); if (!record || record.isTombstone) throw new Error('Ordner fehlt.');
        if (parentID) this.requireFolder(parentID,record.spaceID,valueOf(record).location??'saved');
        let ancestor=parentID; const seen=new Set([id]);
        while (ancestor) {
            if (seen.has(ancestor)) throw new Error('Ordner können nicht in ihre Unterordner verschoben werden.');
            seen.add(ancestor); ancestor=identity(valueOf(this.get('folder',ancestor))?.parentID);
        }
        return this.edit('folder',id,value=>{ if(parentID)value.parentID=wrapped(parentID);else delete value.parentID; });
    }
    reorder(kind,ids,spaceID) {
        const records=ids.map(id=>this.get(kind,id));
        if (new Set(ids).size!==ids.length || records.some(record=>!record || record.isTombstone || (spaceID && record.spaceID!==spaceID))) throw new Error('Ungültige Reihenfolge.');
        const tokens=allocateOrder(records.map(record=>valueOf(record).orderToken));
        records.forEach((record,index)=>{if(valueOf(record).orderToken!==tokens[index])this.edit(kind,record.id,value=>{
            value.orderToken=tokens[index]; if(kind==='tab')value.positionModifiedAt=now();
        });});
    }
    remove(kind,id) {
        const record=this.get(kind,id); if (!record || record.isTombstone) return;
        this.editable(record.spaceID);
        if(kind==='space') for(const child of [...this.live('tab',id),...this.live('folder',id)]) this.tombstone(child);
        if(kind==='folder') {
            // Preserve contents; deleting a folder does not authorize deleting its tabs.
            for(const tab of this.live('tab',record.spaceID).filter(r=>identity(valueOf(r).folderID)===id)) this.edit('tab',tab.id,v=>{delete v.folderID;v.positionModifiedAt=now();});
            for(const child of this.live('folder',record.spaceID).filter(r=>identity(valueOf(r).parentID)===id)) this.edit('folder',child.id,v=>{delete v.parentID;});
        }
        this.tombstone(record);
    }
    tombstone(record) { this.put({...structuredClone(record),version:this.version(),isTombstone:true,body:{reason:'explicitDelete',deletedAt:now()}}); }
    merge(records,cursor,tags={}) {
        // Validate the whole page before accepting its cursor. Unknown/future records stop the pull.
        const prepared=records.map(validateRecord);
        for (const incoming of prepared) {
            this.state.clock=String(BigInt(this.state.clock)>BigInt(incoming.version.clock)?BigInt(this.state.clock):BigInt(incoming.version.clock));
            const key=keyOf(incoming),local=this.state.records[key],merged=mergeRecords(local,incoming);
            this.state.records[key]=merged;
            if (this.state.pending[key]) {
                if (sameRecord(merged,incoming)) delete this.state.pending[key]; else this.state.pending[key]=structuredClone(merged);
            } else if (!sameRecord(merged,incoming)) this.state.pending[key]=structuredClone(merged);
        }
        Object.assign(this.state.serverTags,tags); this.state.cursor=cursor;
    }
    acknowledge(records) {
        for(const record of records) {
            const key=keyOf(record);
            if(sameRecord(this.state.pending[key],record)) delete this.state.pending[key];
        }
    }
}
