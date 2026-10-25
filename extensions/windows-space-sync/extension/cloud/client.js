// SPDX-License-Identifier: MPL-2.0
import {CloudCodec} from './codec.js';
import {keyOf} from '../core/record.js';
export class CloudError extends Error {
    constructor(code='NETWORK_ERROR',retryAfter=0,redirectURL=null) {
        super(({AUTHENTICATION_REQUIRED:'Apple-Anmeldung erforderlich.',CONFLICT:'Gleichzeitige Änderung – beim nächsten Abgleich erneut zusammenführen.',
            WRITE_BLOCKED:'Schreiben ist nur in einer freigegebenen Development-Testzone möglich.',CHANGE_TOKEN_EXPIRED:'CloudKit-Cursor abgelaufen. Erneuter vollständiger Abruf folgt.',
            UNKNOWN_ITEM:'CloudKit-Testzone fehlt. Bitte die Apple-Konfiguration prüfen.',ACCOUNT_CHANGED:'Anderer Apple-Account erkannt. Daten werden nicht vermischt.'})[code]??'CloudKit-Anfrage fehlgeschlagen. Verbindung und Konfiguration prüfen.');
        this.code=code;this.retryAfter=retryAfter;this.redirectURL=redirectURL;
    }
}
export class CloudClient {
    constructor(config,session,fetcher=fetch) {this.config=config;this.session=session;this.fetcher=fetcher;this.tail=Promise.resolve();}
    request(operation,body) {
        const work=()=>this.perform(operation,body);
        const result=this.tail.then(work,work);this.tail=result.catch(()=>{});return result;
    }
    async perform(operation,body) {
        if(!/^iCloud\.[A-Za-z0-9.-]+$/.test(this.config.container) || !['development','production'].includes(this.config.environment) || !this.config.apiToken)
            throw new CloudError('CONFIGURATION');
        const auth=await this.session.get();
        const url=new URL(`https://api.apple-cloudkit.com/database/1/${encodeURIComponent(this.config.container)}/${this.config.environment}/private/${operation}`);
        url.searchParams.set('ckAPIToken',this.config.apiToken);
        if(auth?.token)url.searchParams.set('ckWebAuthToken',auth.token);
        let response,data;
        try {
            response=await this.fetcher(url.href,{method:body?'POST':'GET',headers:body?{'Content-Type':'application/json'}:{},
                ...(body?{body:JSON.stringify(body)}:{}),credentials:'omit',cache:'no-store',redirect:'error',referrerPolicy:'no-referrer',signal:AbortSignal.timeout(20000)});
            const raw=await response.text(); if(raw.length>16000000)throw new Error(); data=JSON.parse(raw);
        } catch { throw new CloudError('NETWORK_ERROR'); }
        // Auth tokens rotate; serialize every request, including pulls and account checks.
        if(typeof data.ckWebAuthToken==='string')await this.session.set({...auth,token:data.ckWebAuthToken});
        if(data.serverErrorCode) {
            if(data.serverErrorCode==='AUTHENTICATION_REQUIRED')await this.session.clear();
            throw new CloudError(data.serverErrorCode,Number(data.retryAfter)||0,data.redirectURL);
        }
        if(!response.ok)throw new CloudError('HTTP_ERROR',Number(response.headers.get('retry-after'))||0);
        return data;
    }
    async currentUser() {
        const result=await this.request('users/current');
        if(typeof result.userRecordName!=='string' || !result.userRecordName)throw new CloudError('AUTHENTICATION_REQUIRED');
        return result.userRecordName;
    }
    async pull(cursor=null) {
        let token=cursor,more=true;const records=[],tags={};let pages=0;
        while(more) {
            if(++pages>1000)throw new CloudError('PAGE_LIMIT');
            const zone={zoneID:{zoneName:this.config.zone},...(token?{syncToken:token}:{})};
            const data=await this.request('changes/zone',{zones:[zone],numberAsStrings:true,resultsLimit:200});
            if(!Array.isArray(data.zones) || data.zones.length!==1)throw new CloudError('MALFORMED_RESPONSE');
            const result=data.zones[0];
            if(result.serverErrorCode)throw new CloudError(result.serverErrorCode,Number(result.retryAfter)||0);
            if(result.zoneID?.zoneName!==this.config.zone || !Array.isArray(result.records) || typeof result.syncToken!=='string')throw new CloudError('MALFORMED_RESPONSE');
            for(const source of result.records) {
                if(source.serverErrorCode)throw new CloudError(source.serverErrorCode);
                const record=CloudCodec.decode(source);
                if(record){records.push(record);if(typeof source.recordChangeTag!=='string')throw new CloudError('MALFORMED_RESPONSE');tags[keyOf(record)]=source.recordChangeTag;}
            }
            more=result.moreComing===true;
            if(more && result.syncToken===token)throw new CloudError('MALFORMED_RESPONSE');
            token=result.syncToken;
            if(records.length>250000)throw new CloudError('RECORD_LIMIT');
        }
        return {records,cursor:token,tags};
    }
    async push(records,tags={}) {
        // Production writes are deliberately unavailable in this preview, even if settings are edited.
        if(this.config.environment!=='development' || !/^CrestReview-[A-Za-z0-9-]{1,80}$/.test(this.config.zone) || this.config.writeEnabled!==true)
            throw new CloudError('WRITE_BLOCKED');
        const acknowledged=[],updatedTags={};
        for(let offset=0;offset<records.length;offset+=100) {
            const batch=records.slice(offset,offset+100);
            const operations=batch.map(record=>({operationType:tags[keyOf(record)]?'update':'create',record:CloudCodec.encode(record,tags[keyOf(record)])}));
            const data=await this.request('records/modify',{zoneID:{zoneName:this.config.zone},atomic:true,operations,numbersAsStrings:true});
            if(!Array.isArray(data.records) || data.records.length!==batch.length)throw new CloudError('MALFORMED_RESPONSE');
            const indexed=new Map(data.records.map(record=>[record.recordName,record]));
            for(const record of batch) {
                const result=indexed.get(keyOf(record));
                if(!result || result.serverErrorCode || typeof result.recordChangeTag!=='string')throw new CloudError(result?.serverErrorCode==='CONFLICT'?'CONFLICT':result?.serverErrorCode??'MALFORMED_RESPONSE',Number(result?.retryAfter)||0);
                const decoded=CloudCodec.decode(result);
                if(!decoded || keyOf(decoded)!==keyOf(record) || decoded.version.clock!==record.version.clock || decoded.version.deviceID!==record.version.deviceID)
                    throw new CloudError('MALFORMED_RESPONSE');
                updatedTags[keyOf(record)]=result.recordChangeTag; acknowledged.push(record);
            }
        }
        return {acknowledged,tags:updatedTags};
    }
}
