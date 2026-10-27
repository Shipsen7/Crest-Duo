// SPDX-License-Identifier: MPL-2.0
const $=id=>document.getElementById(id);let initial=true;
async function send(action,values={}) {
    $('error').hidden=true;
    try {
        const result=await chrome.runtime.sendMessage({action,...values});if(!result?.ok)throw new Error(result?.error??'Erweiterung ist nicht erreichbar.');
        const state=result.state;$('status').textContent=state.status;$('callback').value=state.callback;$('signout').disabled=!state.signedIn;
        if(initial){for(const [key,value]of Object.entries(state.config)){const field=$('config').elements.namedItem(key);if(!field)continue;if(field.type==='checkbox')field.checked=value;else field.value=value;}initial=false;}
        return true;
    }catch(error){$('error').textContent=error.message;$('error').hidden=false;return false;}
}
$('config').onsubmit=async event=>{event.preventDefault();const form=event.currentTarget;const data=new FormData(form);await send('configure',{config:Object.fromEntries([...data.entries()].map(([key,value])=>[key,key==='writeEnabled'?true:value]))});form.elements.namedItem('apiToken').value='';};
$('signin').onclick=async()=>{
    if(await chrome.permissions.request({origins:['https://api.apple-cloudkit.com/*']}))await send('signIn');
    else {$('error').textContent='Ohne die CloudKit-Berechtigung bleibt die Erweiterung lokal.';$('error').hidden=false;}
};
$('signout').onclick=()=>send('signOut');$('sync').onclick=()=>send('sync');
$('guide').href='https://github.com/Shipsen7/Fennavio/tree/feature/windows-spaces-sync-extension/extensions/windows-space-sync';$('guide').target='_blank';$('guide').rel='noreferrer';
await send('state');
