// SPDX-License-Identifier: MPL-2.0
import {CloudError} from './client.js';
export function appleAuthURL(input) {
    let url;try {url=new URL(input);}catch{throw new CloudError('AUTH_REDIRECT');}
    const roots=['apple.com','icloud.com','apple-cloudkit.com'];
    if(url.protocol!=='https:' || url.username || url.password || !roots.some(root=>url.hostname===root || url.hostname.endsWith('.'+root)))throw new CloudError('AUTH_REDIRECT');
    return url.href;
}
export function callbackToken(input,expected) {
    const url=new URL(input),target=new URL(expected);
    if(url.origin!==target.origin || url.pathname!==target.pathname)throw new CloudError('AUTH_CALLBACK');
    const tokens=url.searchParams.getAll('ckWebAuthToken');
    if(tokens.length!==1 || !tokens[0] || tokens[0].length>20000)throw new CloudError('AUTH_CALLBACK');
    return tokens[0];
}
export class AppleAuth {
    constructor(client,identity,session) {this.client=client;this.identity=identity;this.session=session;}
    async signIn() {
        await this.session.clear();
        try {return await this.client.currentUser();}catch(error){
            if(!(error instanceof CloudError) || error.code!=='AUTHENTICATION_REQUIRED' || !error.redirectURL)throw error;
            const expected=this.identity.getRedirectURL('cloudkit');
            let callback;
            try {callback=await this.identity.launchWebAuthFlow({url:appleAuthURL(error.redirectURL),interactive:true});}
            catch {throw new CloudError('AUTH_CANCELLED');}
            if(!callback)throw new CloudError('AUTH_CANCELLED');
            const token=callbackToken(callback,expected);
            await this.session.set({token});
            try{return await this.client.currentUser();}catch(failure){await this.session.clear();throw failure;}
        }
    }
    async signOut() {await this.session.clear();}
}
