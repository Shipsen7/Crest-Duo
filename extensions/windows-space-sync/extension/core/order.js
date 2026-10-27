// SPDX-License-Identifier: MPL-2.0
// Port of CrestCore.Domain.SyncOrderTokens; retain the longest ascending anchors.
export function allocateOrder(existing) {
    if (existing.length > 250000) throw new Error('Zu viele Einträge.');
    const max = 18446744073709551615n;
    const encode = value => value.toString(16).padStart(16,'0');
    const compact = () => existing.map((_, i) => encode(max / BigInt(existing.length + 1) * BigInt(i + 1)));
    const candidates = existing.map((token,index) => ({token,index})).filter(({token}) => /^[0-9a-f]{16}$/.test(token ?? ''))
        .map(({token,index}) => ({index,value:BigInt('0x'+token)}));
    if (!candidates.length) return compact();
    const tails=[], indices=[], predecessors=Array(candidates.length).fill(-1);
    candidates.forEach(({value},i) => {
        let low=0, high=tails.length;
        while (low < high) { const mid=(low+high)>>1; if (tails[mid]<value) low=mid+1; else high=mid; }
        if (low>0) predecessors[i]=indices[low-1];
        tails[low]=value; indices[low]=i;
    });
    const anchors=[];
    for (let i=indices.at(-1); i>=0; i=predecessors[i]) anchors.push(candidates[i]);
    anchors.reverse();
    const result=Array(existing.length); let previous=-1, lower=0n;
    function distribute(start,count,upper) {
        if (!count) return true;
        const step=(upper-lower)/BigInt(count+1);
        if (step<1n) return false;
        for (let i=0;i<count;i++) result[start+i]=encode(lower+step*BigInt(i+1));
        return true;
    }
    for (const anchor of anchors) {
        if (!distribute(previous+1,anchor.index-previous-1,anchor.value)) return compact();
        result[anchor.index]=encode(anchor.value); previous=anchor.index; lower=anchor.value;
    }
    return distribute(previous+1,existing.length-previous-1,max) ? result : compact();
}
