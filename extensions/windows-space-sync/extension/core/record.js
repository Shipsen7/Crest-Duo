// SPDX-License-Identifier: MPL-2.0
// Wire spellings follow CrestCore's existing schema; no new CloudKit record types.
export const kinds = Object.freeze({space: 'CrestSpace', folder: 'CrestFolder', tab: 'CrestTab'});
export const uuid = () => crypto.randomUUID().toLowerCase();
export const identity = value => typeof value === 'string' ? value.toLowerCase() : value?.rawValue?.toLowerCase();
export const wrapped = id => ({rawValue: id.toLowerCase()});
export const keyOf = record => `${record.kind}:${record.id}`;
export const valueOf = record => record?.isTombstone ? null : record?.body?.value;
export const now = () => Date.now() / 1000;
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
export function requireUUID(value) {
    const result = identity(value);
    if (!uuidPattern.test(result ?? '')) throw new Error('Ungültige Datensatz-Identität.');
    return result;
}
export function text(value, limit = 2048) {
    const characters = [...String(value || 'Ohne Titel')];
    let result = '';
    for (const character of characters) {
        if (new TextEncoder().encode(result + character).length > limit) break;
        result += character;
    }
    return result || 'Ohne Titel';
}
export function webURL(input) {
    try {
        const url = new URL(input);
        if (!['http:', 'https:'].includes(url.protocol) || !url.hostname || url.username || url.password) return null;
        return new TextEncoder().encode(url.href).length <= 8192 ? url.href : null;
    } catch { return null; }
}
export function compareVersion(first, second) {
    const a = BigInt(first.clock), b = BigInt(second.clock);
    return a === b ? (first.deviceID < second.deviceID ? -1 : first.deviceID > second.deviceID ? 1 : 0) : a < b ? -1 : 1;
}
export function validateRecord(source) {
    const record = structuredClone(source);
    if (!Object.hasOwn(kinds, record.kind)) throw new Error('Nicht unterstützter Datensatztyp.');
    record.id = requireUUID(record.id);
    record.spaceID = requireUUID(record.spaceID);
    record.version.deviceID = requireUUID(record.version.deviceID);
    if (!/^(0|[1-9][0-9]*)$/.test(String(record.version.clock)) || BigInt(record.version.clock) > 18446744073709551615n)
        throw new Error('Ungültiger Versionszähler.');
    record.version.clock = String(record.version.clock);
    if (!Number.isInteger(record.schema) || record.schema < 1 || record.schema > 3) throw new Error('Unbekannte Schemaversion – Datensatz bleibt unverändert.');
    if (record.kind === 'space' && record.id !== record.spaceID) throw new Error('Space-Identität stimmt nicht überein.');
    if (!record.body || typeof record.body !== 'object' || Array.isArray(record.body)) throw new Error('Ungültiger Datensatzinhalt.');
    if (new TextEncoder().encode(JSON.stringify(record.body)).length > 900000) throw new Error('Datensatz zu groß.');
    if (record.isTombstone) {
        if (!['explicitDelete', 'superseded', 'retention'].includes(record.body.reason) || !Number.isFinite(record.body.deletedAt))
            throw new Error('Ungültige Löschmarkierung.');
    } else {
        const value = record.body.value;
        if (record.body.type !== record.kind || requireUUID(value?.id) !== record.id ||
            (record.kind !== 'space' && requireUUID(value?.spaceID) !== record.spaceID)) throw new Error('Datensatz und Inhalt passen nicht zusammen.');
        if (!/^[0-9a-fA-F]{1,16}$/.test(value.orderToken)) throw new Error('Ungültige Reihenfolge.');
        if (record.kind === 'space') {
            requireUUID(value.profileID);
            if (!value.name || !value.symbol || !value.accent) throw new Error('Unvollständiger Space.');
        }
        if (record.kind === 'tab') {
            if (!['current','saved','pinned'].includes(value.placement) || !Number.isFinite(value.lastActivatedAt) || !value.title || !value.symbol)
                throw new Error('Unvollständiger Tab.');
            if (!value.nativeContent && (!webURL(value.url) || (value.savedURL && !webURL(value.savedURL))))
                throw new Error('Tab enthält keine sichere, portable Webadresse.');
            if (value.folderID) requireUUID(value.folderID);
            if (value.placement === 'pinned' && value.folderID) throw new Error('Angeheftete Tabs können keine Ordner besitzen.');
        }
        if (record.kind === 'folder') {
            if (!value.title || !['saved','current'].includes(value.location ?? 'saved')) throw new Error('Ungültiger Ordner.');
            if (value.parentID && requireUUID(value.parentID) === record.id) throw new Error('Ordner darf nicht sein eigener Elternordner sein.');
        }
    }
    return record;
}
// Match SyncRecordStamp.Winner, with deterministic tie handling for two tombstones.
export function mergeRecords(first, second) {
    if (!first) return validateRecord(second);
    if (!second) return validateRecord(first);
    first = validateRecord(first); second = validateRecord(second);
    if (keyOf(first) !== keyOf(second) || (first.kind !== 'tab' && first.spaceID !== second.spaceID)) throw new Error('Identitätskonflikt.');
    const aDelete = first.isTombstone && first.body.reason === 'explicitDelete';
    const bDelete = second.isTombstone && second.body.reason === 'explicitDelete';
    let winner;
    if (aDelete !== bDelete) winner = aDelete ? first : second;
    else if (first.isTombstone && !second.isTombstone && second.body.value.lastActivatedAt > first.body.deletedAt) winner = second;
    else if (second.isTombstone && !first.isTombstone && first.body.value.lastActivatedAt > second.body.deletedAt) winner = first;
    else winner = compareVersion(first.version, second.version) >= 0 ? first : second;
    const result = structuredClone(winner);
    if (first.isTombstone || second.isTombstone) return result;
    const a = valueOf(first), b = valueOf(second), value = valueOf(result);
    const latest = (stamp, fields) => {
        const source = (a[stamp] ?? -Infinity) > (b[stamp] ?? -Infinity) ? a : (b[stamp] ?? -Infinity) > (a[stamp] ?? -Infinity) ? b : null;
        if (source) for (const field of [stamp, ...fields]) {
            if (Object.hasOwn(source, field)) value[field] = structuredClone(source[field]); else delete value[field];
        }
    };
    if (result.kind === 'tab') {
        value.lastActivatedAt = Math.max(a.lastActivatedAt, b.lastActivatedAt);
        latest('titleModifiedAt', ['customTitle']);
        if ((a.positionModifiedAt ?? null) !== (b.positionModifiedAt ?? null))
            latest('positionModifiedAt', ['placement','folderID','orderToken','splitGroupID']);
        else value.placement = ['pinned','saved','current'].find(placement => [a.placement,b.placement].includes(placement));
        if (value.placement === 'pinned') { delete value.folderID; delete value.splitGroupID; }
    }
    if (result.kind === 'folder') latest('collapseModifiedAt', ['isCollapsed']);
    if (result.kind === 'space') {
        latest('savedTabsExpansionModifiedAt', ['isSavedTabsExpanded']);
        latest('credentialsEnabledModifiedAt', ['credentialsEnabled']);
        latest('accessPolicyModifiedAt', ['accessPolicy']);
    }
    return result;
}
export function makeRecord(kind, id, spaceID, value, version) {
    return validateRecord({kind,id,spaceID,version,schema: kind === 'folder' && value.location === 'current' || kind === 'tab' && value.placement === 'current' && value.folderID ? 2 : 1,
        body:{type:kind,value},isTombstone:false});
}
export function sameRecord(a,b) { return JSON.stringify(a) === JSON.stringify(b); }
