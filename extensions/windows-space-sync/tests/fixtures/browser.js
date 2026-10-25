// SPDX-License-Identifier: MPL-2.0
export class FakeBrowser {
    constructor() {
        this.tabList=[];this.groupList=[];this.closed=[];this.nextID=10;this.windowsList=[{id:1,incognito:false}];
        this.tabs={query:async filter=>structuredClone(this.tabList.filter(tab=>Object.entries(filter??{}).every(([key,value])=>tab[key]===value))),get:async id=>{const tab=this.tabList.find(t=>t.id===id);if(!tab)throw new Error('Tab missing');return structuredClone(tab);},
            create:async properties=>{const tab={id:this.nextID++,groupId:-1,index:this.tabList.length,windowId:1,incognito:false,pinned:false,title:new URL(properties.url).hostname,...properties};this.tabList.push(tab);return structuredClone(tab);},
            update:async(id,properties)=>{const tab=this.tabList.find(t=>t.id===id);Object.assign(tab,properties);if(tab.pinned)tab.groupId=-1;return structuredClone(tab);},
            remove:async id=>{this.closed.push(id);this.tabList=this.tabList.filter(t=>t.id!==id);},
            group:async properties=>{let groupId=properties.groupId;if(groupId===undefined){groupId=this.nextID++;this.groupList.push({id:groupId,title:'',color:'grey',windowId:1,incognito:false});}for(const id of properties.tabIds)this.tabList.find(t=>t.id===id).groupId=groupId;return groupId;},
            move:async(id,properties)=>{const index=this.tabList.findIndex(t=>t.id===id),[tab]=this.tabList.splice(index,1);if(properties.windowId!==undefined)tab.windowId=properties.windowId;this.tabList.splice(properties.index<0?this.tabList.length:properties.index,0,tab);this.tabList.forEach((t,i)=>t.index=i);return structuredClone(tab);}};
        this.tabGroups={query:async filter=>structuredClone(this.groupList.filter(group=>Object.entries(filter??{}).every(([key,value])=>group[key]===value))),get:async id=>structuredClone(this.groupList.find(g=>g.id===id)),update:async(id,props)=>Object.assign(this.groupList.find(g=>g.id===id),props),move:async(id,properties)=>{const group=this.groupList.find(g=>g.id===id),members=this.tabList.filter(tab=>tab.groupId===id);this.tabList=this.tabList.filter(tab=>tab.groupId!==id);this.tabList.splice(properties.index<0?this.tabList.length:properties.index,0,...members);this.tabList.forEach((tab,index)=>tab.index=index);return structuredClone(group);}};
        this.windows={getAll:async()=>structuredClone(this.windowsList)};
    }
    group(title='Arbeit',id=1){const group={id,title,color:'blue',windowId:1,incognito:false};this.groupList.push(group);return group;}
    tab(url='https://example.org/',groupId=1,id=2){const tab={id,url,title:'Test',groupId,windowId:1,index:this.tabList.length,pinned:false,incognito:false};this.tabList.push(tab);return tab;}
}
