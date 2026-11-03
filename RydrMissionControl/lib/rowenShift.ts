export function rowenShift(now = new Date()) {
 const p=Object.fromEntries(new Intl.DateTimeFormat('en-CA',{timeZone:'America/New_York',weekday:'short',hour:'2-digit',minute:'2-digit',hourCycle:'h23'}).formatToParts(now).map(p=>[p.type,p.value]));
 const minute=Number(p.hour)*60+Number(p.minute), weekday=!['Sat','Sun'].includes(p.weekday);
 const breaks=[{start:645,end:660,label:'On Break',resume:'11:00 a.m.'},{start:750,end:780,label:'On Lunch',resume:'1:00 p.m.'},{start:900,end:915,label:'On Break',resume:'3:15 p.m.'}];
 const pause=weekday?breaks.find(b=>minute>=b.start&&minute<b.end):undefined;
 const onShift=weekday&&minute>=540&&minute<1020;
 return {onShift,canWork:onShift&&!pause,label:pause?.label??(!onShift?'Off shift':minute>=1005?'Ending Shift':'On shift'),resume:pause?.resume??null,minute};
}
