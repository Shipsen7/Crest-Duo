// SPDX-License-Identifier: MPL-2.0
import {valueOf,identity} from '../core/record.js';
let state;
const $=id=>document.getElementById(id);
const element=(tag,text,attributes={})=>{const node=document.createElement(tag);if(text!==undefined)node.textContent=text;for(const [key,value]of Object.entries(attributes))node.setAttribute(key,value);return node;};
async function send(action,values={},passive=false) {
    $('error').hidden=true;
    try {
        const result=await chrome.runtime.sendMessage({action,...values});
        if(!result?.ok)throw new Error(result?.error??'Erweiterung ist nicht erreichbar.');state=result.state;const editing=passive && ['INPUT','SELECT','TEXTAREA'].includes(document.activeElement?.tagName) && document.activeElement?.id!=='search';if(!editing)render();else $('status').textContent=state.status;return true;
    }catch(error){$('error').textContent=error.message;$('error').hidden=false;return false;}
}
const button=(label,action,values={},attributes={})=>{const node=element('button',label,{type:'button',...attributes});node.onclick=()=>send(action,typeof values==='function'?values():values);return node;};
function input(form,label,name,value='',type='text') {
    const wrapper=element('label',label),control=element('input',undefined,{name,type});control.value=value;wrapper.append(control);form.append(wrapper);return control;
}
function select(form,label,name,choices,value) {
    const wrapper=element('label',label),control=element('select',undefined,{name});
    for(const [id,title]of choices){const option=element('option',title,{value:id});control.append(option);}control.value=value??'';wrapper.append(control);form.append(wrapper);return control;
}
function submit(form,label,handler) {
    const control=element('button',label);form.append(control);form.onsubmit=async event=>{event.preventDefault();control.disabled=true;try{await handler(new FormData(form));}finally{control.disabled=false;}};
}
function details(label) {const node=element('details');node.append(element('summary',label));return node;}
function live(kind,spaceID) {return Object.values(state.records).filter(r=>r.kind===kind && !r.isTombstone && (!spaceID || r.spaceID===spaceID)).sort((a,b)=>valueOf(a).orderToken.localeCompare(valueOf(b).orderToken)||a.id.localeCompare(b.id));}
function removeControl(parent,kind,id) {
    const form=element('form');const check=input(form,kind==='space'?'Diesen Space samt Tabs und Ordnern löschen':'Diesen Eintrag löschen','confirm','','checkbox');check.required=true;
    submit(form,'Löschen',()=>send('remove',{kind,id}));form.lastElementChild.className='danger';parent.append(form);
}
function orderButtons(parent,record,siblings) {
    const index=siblings.findIndex(r=>r.id===record.id),wrap=element('span');
    for(const [delta,label]of [[-1,'↑'],[1,'↓']]) {
        const control=button(label,'reorder',()=>{const ids=siblings.map(r=>r.id);[ids[index],ids[index+delta]]=[ids[index+delta],ids[index]];return{kind:record.kind,ids,spaceID:record.kind==='space'?null:record.spaceID};},{'aria-label':label==='↑'?'Nach oben':'Nach unten'});
        control.disabled=index+delta<0||index+delta>=siblings.length;wrap.append(control);
    }parent.append(wrap);
}
function tabRow(record,siblings) {
    const value=valueOf(record),node=element('div'),row=element('div',undefined,{class:'row'});
    const title=value.customTitle||value.title;row.append(button(title,'openTab',{id:record.id},{class:'name'}));
    row.append(element('span',({pinned:'Angeheftet',saved:'Gespeichert',current:'Offen'})[value.placement],{class:'tag'}));orderButtons(row,record,siblings);node.append(row);
    node.append(element('span',value.url??'Nativer Fennavio-Inhalt',{class:'url'}));
    if(value.nativeContent){node.append(element('small','Native Inhalte werden unter Windows nicht geöffnet oder bearbeitet.'));return node;}
    const edit=details('Bearbeiten'),rename=element('form');input(rename,'Name','name',title);submit(rename,'Umbenennen',data=>send('rename',{kind:'tab',id:record.id,name:data.get('name')}));edit.append(rename);
    const move=element('form');select(move,'Space','spaceID',live('space').filter(r=>(valueOf(r).accessPolicy??'open')==='open').map(r=>[r.id,valueOf(r).name]),record.spaceID);
    const placement=select(move,'Bereich','placement',[['current','Offen'],['pinned','Angeheftet'],['saved','Gespeichert']],value.placement);
    const folder=select(move,'Ordner','folderID',[['','Ohne Ordner'],...live('folder',record.spaceID).filter(r=>(valueOf(r).location??'saved')===placement.value).map(r=>[r.id,valueOf(r).title])],identity(value.folderID));
    placement.onchange=()=>{folder.value='';folder.disabled=true;};
    submit(move,'Verschieben',data=>send('moveTab',{id:record.id,spaceID:data.get('spaceID'),placement:data.get('placement'),folderID:data.get('folderID')}));edit.append(move);removeControl(edit,'tab',record.id);node.append(edit);return node;
}
function folderNode(record,folders,tabs,visited=new Set()) {
    if(visited.has(record.id))return element('p','Zyklische Ordnerstruktur – bitte auf dem Apple-Gerät prüfen.');
    visited=new Set(visited).add(record.id);const value=valueOf(record),node=element('div',undefined,{class:'folder'}),heading=element('div',undefined,{class:'row'});
    heading.append(element('h3',value.title));orderButtons(heading,record,folders);node.append(heading);
    const edit=details('Ordner bearbeiten'),rename=element('form');input(rename,'Name','name',value.title);submit(rename,'Umbenennen',data=>send('rename',{kind:'folder',id:record.id,name:data.get('name')}));edit.append(rename);
    const move=element('form');select(move,'Elternordner','parentID',[['','Oberste Ebene'],...folders.filter(r=>r.id!==record.id && (valueOf(r).location??'saved')===(value.location??'saved')).map(r=>[r.id,valueOf(r).title])],identity(value.parentID));submit(move,'Ordner verschieben',data=>send('moveFolder',{id:record.id,parentID:data.get('parentID')}));edit.append(move);removeControl(edit,'folder',record.id);node.append(edit);
    for(const tab of tabs.filter(r=>identity(valueOf(r).folderID)===record.id))node.append(tabRow(tab,tabs));
    for(const child of folders.filter(r=>identity(valueOf(r).parentID)===record.id))node.append(folderNode(child,folders,tabs,visited));return node;
}
function render() {
    $('status').textContent=state.status+(state.lastSync?' · '+new Date(state.lastSync).toLocaleString('de-DE'):'');
    $('pending').textContent=`${state.pendingCount} lokale Änderungen vorgemerkt`;$('hold').hidden=!state.deletionHold;
    const all=live('space'),query=$('search').value.toLowerCase().trim(),root=$('spaces');root.replaceChildren();$('empty').hidden=all.length>0;
    for(const space of all) {
        const value=valueOf(space),folders=live('folder',space.id),tabs=live('tab',space.id);
        if(query && ![value.name,...folders.map(r=>valueOf(r).title),...tabs.map(r=>(valueOf(r).customTitle||valueOf(r).title)+' '+valueOf(r).url)].some(t=>t.toLowerCase().includes(query)))continue;
        const section=element('section',undefined,{class:'space'}),heading=element('div',undefined,{class:'row'});heading.append(element('h2',value.name));orderButtons(heading,space,all);section.append(heading);
        if((value.accessPolicy??'open')!=='open'){section.append(element('p','Geschützter Space – keine Darstellung oder Bearbeitung unter Windows.'));root.append(section);continue;}
        section.append(button('Space öffnen','openSpace',{id:space.id}));
        const edit=details('Space bearbeiten'),rename=element('form');input(rename,'Name','name',value.name);submit(rename,'Umbenennen',data=>send('rename',{kind:'space',id:space.id,name:data.get('name')}));edit.append(rename);
        const colors=element('form');select(colors,'Chromium-Farbe (auf Apple angenähert)','color',['grey','blue','red','yellow','green','pink','purple','cyan','orange'].map(color=>[color,color]),state.colors?.[space.id]??({indigo:'blue',teal:'cyan',rose:'pink',orange:'orange'})[value.accent]);submit(colors,'Farbe ändern',data=>send('color',{id:space.id,color:data.get('color')}));edit.append(colors);removeControl(edit,'space',space.id);section.append(edit);
        const addFolder=details('Ordner hinzufügen'),folderForm=element('form');input(folderForm,'Name','name');select(folderForm,'Elternordner','parentID',[['','Oberste Ebene'],...folders.map(r=>[r.id,valueOf(r).title])]);select(folderForm,'Bereich','location',[['saved','Gespeichert'],['current','Offen']]);submit(folderForm,'Ordner hinzufügen',data=>send('addFolder',{spaceID:space.id,name:data.get('name'),parentID:data.get('parentID'),location:data.get('location')}));addFolder.append(folderForm);section.append(addFolder);
        const addTab=details('Tab hinzufügen'),tabForm=element('form');input(tabForm,'Adresse (https://…)','url','','url').required=true;input(tabForm,'Name (optional)','name');select(tabForm,'Bereich','placement',[['saved','Gespeichert'],['current','Offen'],['pinned','Angeheftet']]);select(tabForm,'Ordner (muss zum Bereich passen)','folderID',[['','Ohne Ordner'],...folders.map(r=>[r.id,valueOf(r).title])]);submit(tabForm,'Tab hinzufügen',data=>send('addTab',{spaceID:space.id,url:data.get('url'),name:data.get('name'),placement:data.get('placement'),folderID:data.get('folderID')}));addTab.append(tabForm);section.append(addTab);
        for(const tab of tabs.filter(r=>!valueOf(r).folderID || !folders.some(f=>f.id===identity(valueOf(r).folderID))))section.append(tabRow(tab,tabs));
        for(const folder of folders.filter(r=>!valueOf(r).parentID || !folders.some(f=>f.id===identity(valueOf(r).parentID))))section.append(folderNode(folder,folders,tabs));
        root.append(section);
    }
}
$('sync').onclick=()=>send('sync');$('capture').onclick=()=>send('capture');$('approve').onclick=()=>send('approveDeletions');$('options').onclick=()=>chrome.runtime.openOptionsPage();
$('expand').onclick=()=>chrome.tabs.create({url:chrome.runtime.getURL('ui/popup.html?expanded=1')});
if(new URL(location.href).searchParams.has('expanded')){document.body.classList.add('expanded');$('expand').hidden=true;}
$('search').oninput=()=>{if(state)render();};$('new-space').onsubmit=async event=>{event.preventDefault();const form=event.currentTarget;if(await send('addSpace',{name:new FormData(form).get('name')}))form.reset();};
await send('state');
chrome.storage.onChanged.addListener((changes,area)=>{if(area==='local' && changes.workspace)send('state',{},true);});
