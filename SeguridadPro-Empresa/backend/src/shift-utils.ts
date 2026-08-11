export const timeMinutes=(value:string)=>{if(!/^([01]\d|2[0-3]):[0-5]\d$/.test(value))throw new Error('Horario inválido');const[h,m]=value.split(':').map(Number);return h*60+m};
export const shiftHours=(start:string,end:string)=>{const a=timeMinutes(start),b=timeMinutes(end);return((b>a?b:b+1440)-a)/60};
export const overlaps=(aStart:Date,aEnd:Date,bStart:Date,bEnd:Date)=>aStart<bEnd&&bStart<aEnd;
