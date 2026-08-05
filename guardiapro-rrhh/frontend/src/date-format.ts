type DisplaySettings={timezone:string;date_format:string;time_format:string};
let settings:DisplaySettings={timezone:'America/Santiago',date_format:'DD/MM/YYYY',time_format:'24h'};
export const configureDateDisplay=(next:Partial<DisplaySettings>)=>{settings={...settings,...next}};
const locale=()=>settings.date_format==='MM/DD/YYYY'?'en-US':settings.date_format==='YYYY-MM-DD'?'en-CA':'es-CL';
const dateParts=()=>settings.date_format==='YYYY-MM-DD'?{year:'numeric',month:'2-digit',day:'2-digit'}as const:{day:'2-digit',month:'2-digit',year:'numeric'}as const;
export function formatDate(value:string|Date){const date=new Date(value);return Number.isNaN(date.getTime())?'Fecha inválida':date.toLocaleDateString(locale(),{...dateParts(),timeZone:settings.timezone})}
export function formatDateTime(value:string|Date,seconds=false){const date=new Date(value);return Number.isNaN(date.getTime())?'Fecha y hora inválidas':date.toLocaleString(locale(),{...dateParts(),timeZone:settings.timezone,hour:'2-digit',minute:'2-digit',...(seconds?{second:'2-digit'}:{}),hour12:settings.time_format==='12h'})}
export function formatTime(value:string|Date,seconds=true){const date=new Date(value);return Number.isNaN(date.getTime())?'Hora inválida':date.toLocaleTimeString(locale(),{timeZone:settings.timezone,hour:'2-digit',minute:'2-digit',...(seconds?{second:'2-digit'}:{}),hour12:settings.time_format==='12h'})}
