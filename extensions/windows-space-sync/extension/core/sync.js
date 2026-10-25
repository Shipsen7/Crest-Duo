// SPDX-License-Identifier: MPL-2.0
import {CloudError} from '../cloud/client.js';
export class SyncEngine {
    constructor(workspace,transport,save) {this.workspace=workspace;this.transport=transport;this.save=save;}
    async run() {
        const state=this.workspace.state;
        const account=await this.transport.currentUser();
        if(state.account && state.account!==account)throw new CloudError('ACCOUNT_CHANGED');
        state.account=account;
        let pulled;
        try {pulled=await this.transport.pull(state.cursor);}
        catch(error) {
            if(error.code==='CHANGE_TOKEN_EXPIRED') {state.cursor=null;await this.save();pulled=await this.transport.pull(null);}
            else throw error;
        }
        this.workspace.merge(pulled.records,pulled.cursor,pulled.tags);
        // The records, cursor and outbox are one storage commit before upload.
        await this.save();
        if(state.config.writeEnabled && Object.keys(state.pending).length) {
            const sent=structuredClone(Object.values(state.pending));
            const result=await this.transport.push(sent,state.serverTags);
            this.workspace.acknowledge(result.acknowledged);Object.assign(state.serverTags,result.tags);
        }
        state.lastSync=Date.now();state.status=state.config.writeEnabled?'Development-Testzone abgeglichen':'CloudKit gelesen · Schreiben gesperrt';
        await this.save();
    }
}
