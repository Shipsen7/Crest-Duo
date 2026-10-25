// SPDX-License-Identifier: MPL-2.0
import {kinds,keyOf,requireUUID,validateRecord} from '../core/record.js';
const encodeBytes = object => {
    const bytes=new TextEncoder().encode(JSON.stringify(sortKeys(object)));
    let binary=''; for(const byte of bytes)binary+=String.fromCharCode(byte);
    return btoa(binary);
};
function sortKeys(value) {
    if(Array.isArray(value))return value.map(sortKeys);
    if(value && typeof value==='object') return Object.fromEntries(Object.keys(value).sort().map(key=>[key,sortKeys(value[key])]));
    return value;
}
function decodeBytes(value) {
    if(typeof value!=='string' || value.length>1300000)throw new Error('CloudKit-Inhalt ist zu groß oder ungültig.');
    const binary=atob(value),bytes=Uint8Array.from(binary,c=>c.charCodeAt(0));
    return JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));
}
export class CloudCodec {
    static encode(source,recordChangeTag) {
        const record=validateRecord(source);
        const fields={schemaVersion:{value:record.schema,type:'INT64'},spaceID:{value:record.spaceID,type:'STRING'},
            logicalClock:{value:record.version.clock,type:'INT64'},deviceID:{value:record.version.deviceID,type:'STRING'},
            payload:record.isTombstone?null:{value:encodeBytes(record.body),type:'BYTES',isEncrypted:true},
            tombstone:record.isTombstone?{value:encodeBytes(record.body),type:'BYTES',isEncrypted:true}:null};
        if(record.kind!=='space')fields.space={value:{recordName:`space:${record.spaceID}`,action:'NONE'},type:'REFERENCE'};
        return {recordName:keyOf(record),recordType:kinds[record.kind],fields,...(recordChangeTag?{recordChangeTag}:{})};
    }
    static decode(source) {
        const [kind,id,...extra]=(source.recordName??'').split(':');
        if(!Object.hasOwn(kinds,kind))return null; // History/archive are intentionally untouched.
        if(extra.length || source.recordType!==kinds[kind])throw new Error('CloudKit-Identität und Typ stimmen nicht überein.');
        if(source.deleted)throw new Error('CloudKit meldet eine physische Löschung. Lokaler Bestand bleibt erhalten; Prüfung erforderlich.');
        if(typeof source.fields?.logicalClock?.value==='number' && !Number.isSafeInteger(source.fields.logicalClock.value))throw new Error('CloudKit lieferte einen ungenauen Versionszähler.');
        const fields=source.fields??{},payload=fields.payload?.value,tombstone=fields.tombstone?.value;
        if((payload==null)===(tombstone==null))throw new Error('CloudKit enthält keinen eindeutig lesbaren Inhalt.');
        const field=payload!=null?fields.payload:fields.tombstone;
        // Never silently substitute an unencrypted field for the browser's encrypted payload.
        if(field.type!=='BYTES' || field.isEncrypted!==true)throw new Error('Verschlüsselungskennzeichnung fehlt. Web-Kompatibilität muss geprüft werden.');
        return validateRecord({kind,id:requireUUID(id),spaceID:requireUUID(fields.spaceID?.value),schema:Number(fields.schemaVersion?.value),
            version:{clock:String(fields.logicalClock?.value),deviceID:requireUUID(fields.deviceID?.value)},
            body:decodeBytes(payload??tombstone),isTombstone:tombstone!=null});
    }
}
