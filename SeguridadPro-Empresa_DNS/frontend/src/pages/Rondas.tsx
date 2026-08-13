import { useEffect, useMemo, useRef, useState } from 'react';
import { MapContainer, Marker, Polyline, Popup, TileLayer, useMap } from 'react-leaflet';
import { CalendarDays, ChevronLeft, ChevronRight, Eye, List, LocateFixed, Play, Plus, Square, Trash2 } from 'lucide-react';
import { api, useAuth } from '../state';
import { Badge, Button, Dialog, PageHead, toneFor } from '../components';

type Point={lat:number;lng:number;timestamp:string;accuracy?:number};
type PeriodView='day'|'week'|'month'|'list';
const hav=(a:Point,b:Point)=>{const R=6371000,dLat=(b.lat-a.lat)*Math.PI/180,dLng=(b.lng-a.lng)*Math.PI/180,x=Math.sin(dLat/2)**2+Math.cos(a.lat*Math.PI/180)*Math.cos(b.lat*Math.PI/180)*Math.sin(dLng/2)**2;return 2*R*Math.atan2(Math.sqrt(x),Math.sqrt(1-x))};
const distanceOf=(points:Point[])=>points.slice(1).reduce((total,point,index)=>total+hav(points[index],point),0);
const routeOf=(value:any):Point[]=>Array.isArray(value)?value.filter(point=>Number.isFinite(point?.lat)&&Number.isFinite(point?.lng)):[];
const startOfDay=(value:Date)=>new Date(value.getFullYear(),value.getMonth(),value.getDate());
const addDays=(value:Date,days:number)=>{const date=new Date(value);date.setDate(date.getDate()+days);return date};
const sameDay=(a:Date,b:Date)=>a.getFullYear()===b.getFullYear()&&a.getMonth()===b.getMonth()&&a.getDate()===b.getDate();
const weekStart=(value:Date)=>addDays(startOfDay(value),-((value.getDay()+6)%7));

function FollowRoute({points}:{points:Point[]}){
  const map=useMap();
  useEffect(()=>{
    if(points.length===1)map.setView([points[0].lat,points[0].lng],17);
    if(points.length>1)map.fitBounds(points.map(point=>[point.lat,point.lng] as [number,number]),{padding:[30,30]});
  },[map,points]);
  return null;
}

export default function Rondas(){
  const{user}=useAuth();
  const canEdit=user?.role==='admin'||(user?.permisos?.rondas===true&&user?.permisos?.editar_rondas===true);
  const canDelete=user?.role==='admin'||user?.permisos?.eliminar_rondas===true;
  const[items,setItems]=useState<any[]>([]);
  const[guardias,setGuardias]=useState<any[]>([]);
  const[recintos,setRecintos]=useState<any[]>([]);
  const[selected,setSelected]=useState<any>();
  const[open,setOpen]=useState(false);
  const[tracking,setTracking]=useState(false);
  const[locating,setLocating]=useState(false);
  const[periodView,setPeriodView]=useState<PeriodView>('week');
  const[anchorDate,setAnchorDate]=useState(()=>startOfDay(new Date()));
  const[route,setRoute]=useState<Point[]>([]);
  const[gpsMessage,setGpsMessage]=useState('');
  const[draft,setDraft]=useState({guardia_nombre:'',recinto_nombre:'',novedades:''});
  const[createdInDialog,setCreatedInDialog]=useState<any>();
  const[dialogStartedAt,setDialogStartedAt]=useState<Date>(()=>new Date());
  const watch=useRef<number|undefined>(undefined);
  const routeRef=useRef<Point[]>([]);
  const lastSync=useRef(0);
  const trackingRef=useRef(false);

  const load=async()=>{const response=await api('/ronda?limit=500');setItems(response.data);setSelected((current:any)=>response.data.find((item:any)=>item.id===current?.id)||response.data[0])};
  useEffect(()=>{
    load();
    Promise.all([api('/lookups/guardias'),api('/lookups/recintos')]).then(([g,r])=>{setGuardias(g);setRecintos(r)});
    const refresh=window.setInterval(()=>{if(!trackingRef.current)load()},10000);
    return()=>{window.clearInterval(refresh);if(watch.current!==undefined)navigator.geolocation.clearWatch(watch.current)};
  },[]);

  const syncRoute=async(rondaId:string,points:Point[])=>api('/ronda/'+rondaId,{method:'PUT',body:JSON.stringify({ruta:points,distancia_m:distanceOf(points),estado:'En_curso'})});
  const readPosition=()=>new Promise<GeolocationPosition>((resolve,reject)=>navigator.geolocation.getCurrentPosition(resolve,reject,{enableHighAccuracy:true,maximumAge:0,timeout:15000}));
  const pointOf=(position:GeolocationPosition):Point=>({lat:position.coords.latitude,lng:position.coords.longitude,accuracy:position.coords.accuracy,timestamp:new Date().toISOString()});
  const gpsError=(error:GeolocationPositionError)=>({1:'Permiso de ubicación rechazado. Activa el GPS y autoriza este sitio.',2:'No fue posible obtener la ubicación. Comprueba que el GPS esté activo.',3:'La ubicación tardó demasiado. Intenta en un lugar con mejor señal.'}[error.code]||error.message);
  const start=async(target=selected)=>{
    if(!target)return alert('Crea una ronda antes de iniciarla');
    if(target.estado==='Completada')return setGpsMessage('Esta ronda ya está completada. Crea una ronda nueva.');
    if(!window.isSecureContext)return setGpsMessage('El GPS requiere acceso mediante HTTPS. Abre Seguridad-RRHH con un dominio seguro para iniciar el seguimiento.');
    if(!navigator.geolocation)return setGpsMessage('Este dispositivo o navegador no ofrece geolocalización.');
    if(tracking||locating)return;
    setLocating(true);setGpsMessage('Activando GPS y obteniendo la ubicación inicial…');
    try{
      const position=await readPosition();
      const initial=[...routeOf(target.ruta),pointOf(position)];
      routeRef.current=initial;setRoute(initial);
      const updated=await api('/ronda/'+target.id,{method:'PUT',body:JSON.stringify({estado:'En_curso',fecha_hora_inicio:target.fecha_hora_inicio,fecha_hora_fin:null,ruta:initial,distancia_m:distanceOf(initial)})});
      setSelected(updated);setCreatedInDialog(updated);
      setTracking(true);trackingRef.current=true;lastSync.current=0;
      setGpsMessage(`Ronda iniciada · GPS activo · precisión ${Math.round(position.coords.accuracy)} m`);
      watch.current=navigator.geolocation.watchPosition(position=>{
        const point=pointOf(position);
        const previous=routeRef.current[routeRef.current.length-1];
        if(previous&&hav(previous,point)<2)return;
        const next=[...routeRef.current,point];routeRef.current=next;setRoute(next);
        setGpsMessage(`GPS activo · precisión ${Math.round(position.coords.accuracy)} m · ${next.length} puntos`);
        if(Date.now()-lastSync.current>=10000){lastSync.current=Date.now();syncRoute(target.id,next).catch(()=>setGpsMessage('GPS activo, pero no se pudo sincronizar el último avance.'))}
      },error=>{
        setGpsMessage(gpsError(error));
      },{enableHighAccuracy:true,maximumAge:2000,timeout:15000});
    }catch(error){setGpsMessage('code' in (error as object)?gpsError(error as GeolocationPositionError):(error as Error).message)}
    finally{setLocating(false)}
  };
  const stop=async()=>{
    if(!tracking||locating)return;
    setLocating(true);setGpsMessage('Obteniendo ubicación final para terminar la ronda…');
    try{
      const finalPoint=pointOf(await readPosition());
      const previous=routeRef.current[routeRef.current.length-1];
      const points=previous&&hav(previous,finalPoint)<2?routeRef.current:[...routeRef.current,finalPoint];
      const updated=await api('/ronda/'+selected.id,{method:'PUT',body:JSON.stringify({ruta:points,distancia_m:distanceOf(points),fecha_hora_fin:new Date().toISOString(),estado:'Completada'})});
      if(watch.current!==undefined){navigator.geolocation.clearWatch(watch.current);watch.current=undefined}
      setTracking(false);trackingRef.current=false;
      setSelected(updated);setCreatedInDialog(updated);setRoute([]);routeRef.current=[];setGpsMessage(`Ronda finalizada con ${points.length} puntos registrados.`);await load();setOpen(false);
    }catch(error){setGpsMessage('No se pudo terminar la ronda sin una ubicación GPS válida. '+('code' in (error as object)?gpsError(error as GeolocationPositionError):(error as Error).message))}
    finally{setLocating(false)}
  };
  const viewRoute=(ronda:any)=>{setSelected(ronda);setRoute([]);routeRef.current=[];setGpsMessage(routeOf(ronda.ruta).length?'Ruta guardada cargada en el mapa.':'Esta ronda todavía no tiene puntos GPS.')};
  const shown=route.length?route:routeOf(selected?.ruta);
  const openNew=()=>{const now=new Date();setDialogStartedAt(now);setDraft({guardia_nombre:guardias[0]?.nombre||'',recinto_nombre:recintos[0]?.nombre||'',novedades:''});setCreatedInDialog(undefined);setGpsMessage('');setOpen(true)};
  const createAndStart=async()=>{try{let ronda=createdInDialog;if(!ronda){const guardia=guardias.find(item=>item.nombre===(draft.guardia_nombre||guardias[0]?.nombre));const recinto=recintos.find(item=>item.nombre===(draft.recinto_nombre||recintos[0]?.nombre));if(!guardia||!recinto)throw new Error('Debes seleccionar un guardia y un recinto');ronda=await api('/ronda',{method:'POST',body:JSON.stringify({...draft,fecha_hora_inicio:dialogStartedAt.toISOString(),estado:'Programada',guardia_id:guardia.id,guardia_nombre:guardia.nombre,recinto_id:recinto.id,recinto_nombre:recinto.nombre,ruta:[],distancia_m:0})});setSelected(ronda);setCreatedInDialog(ronda);await load()}await start(ronda)}catch(error){setGpsMessage((error as Error).message)}};

  const range=useMemo(()=>{
    if(periodView==='day')return{start:startOfDay(anchorDate),end:addDays(startOfDay(anchorDate),1)};
    if(periodView==='week'){const start=weekStart(anchorDate);return{start,end:addDays(start,7)}}
    if(periodView==='month'){const start=new Date(anchorDate.getFullYear(),anchorDate.getMonth(),1);return{start,end:new Date(anchorDate.getFullYear(),anchorDate.getMonth()+1,1)}}
    return null;
  },[anchorDate,periodView]);
  const visibleItems=useMemo(()=>items.filter(item=>!range||((date=>date>=range.start&&date<range.end)(new Date(item.fecha_hora_inicio)))),[items,range]);
  const weekDays=Array.from({length:7},(_,index)=>addDays(weekStart(anchorDate),index));
  const weekRows=useMemo(()=>{
    const rows=new Map<string,{id:string;nombre:string;rango?:string}>();
    guardias.forEach(guardia=>rows.set(guardia.id,{id:guardia.id,nombre:guardia.nombre,rango:guardia.rango}));
    visibleItems.forEach(item=>{
      const id=item.guardia_id||item.guardia_nombre||'sin-guardia';
      if(!rows.has(id))rows.set(id,{id,nombre:item.guardia_nombre||'Sin guardia asignado'});
    });
    return Array.from(rows.values()).sort((a,b)=>a.nombre.localeCompare(b.nombre,'es'));
  },[guardias,visibleItems]);
  const periodLabel=periodView==='list'?'Todas las rondas':periodView==='day'?anchorDate.toLocaleDateString('es-CL',{weekday:'long',day:'numeric',month:'long'}):periodView==='week'?`${range!.start.toLocaleDateString('es-CL',{day:'numeric',month:'short'})} – ${addDays(range!.end,-1).toLocaleDateString('es-CL',{day:'numeric',month:'short',year:'numeric'})}`:anchorDate.toLocaleDateString('es-CL',{month:'long',year:'numeric'});
  const movePeriod=(direction:number)=>setAnchorDate(current=>periodView==='day'?addDays(current,direction):periodView==='week'?addDays(current,direction*7):new Date(current.getFullYear(),current.getMonth()+direction,1));
  const monthStart=new Date(anchorDate.getFullYear(),anchorDate.getMonth(),1);
  const calendarStart=addDays(monthStart,-((monthStart.getDay()+6)%7));
  const calendarDays=Array.from({length:42},(_,index)=>addDays(calendarStart,index));
  const periodControls=<section className="mb-5 rounded-2xl border border-slate-200 bg-white p-4 shadow-sm dark:border-slate-800 dark:bg-slate-900">
    <div className="flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
      <div className="flex flex-wrap gap-2">{([['day','Día'],['week','Semana'],['month','Mes'],['list','Lista']] as [PeriodView,string][]).map(([value,label])=><button key={value} onClick={()=>setPeriodView(value)} className={`inline-flex items-center gap-2 rounded-xl px-3 py-2 text-sm font-semibold transition ${periodView===value?'bg-teal-600 text-white':'bg-slate-100 text-slate-600 hover:bg-slate-200 dark:bg-slate-800 dark:text-slate-200'}`}>{value==='month'?<CalendarDays size={16}/>:value==='list'?<List size={16}/>:null}{label}</button>)}</div>
      <div className="flex items-center justify-between gap-2 lg:justify-end"><button onClick={()=>movePeriod(-1)} disabled={periodView==='list'} className="rounded-lg p-2 hover:bg-slate-100 disabled:opacity-30 dark:hover:bg-slate-800" aria-label="Periodo anterior"><ChevronLeft size={20}/></button><button onClick={()=>setAnchorDate(startOfDay(new Date()))} className="rounded-lg px-3 py-2 text-sm font-semibold hover:bg-slate-100 dark:hover:bg-slate-800">Hoy</button><button onClick={()=>movePeriod(1)} disabled={periodView==='list'} className="rounded-lg p-2 hover:bg-slate-100 disabled:opacity-30 dark:hover:bg-slate-800" aria-label="Periodo siguiente"><ChevronRight size={20}/></button></div>
    </div>
    <div className="mt-4 flex flex-wrap items-center justify-between gap-2"><h2 className="font-bold capitalize text-slate-800 dark:text-white">{periodLabel}</h2><span className="rounded-full bg-teal-50 px-3 py-1 text-sm font-semibold text-teal-700 dark:bg-teal-950 dark:text-teal-200">{visibleItems.length} {visibleItems.length===1?'ronda':'rondas'}</span></div>
    {periodView==='week'&&<div className="mt-4 overflow-x-auto rounded-xl border border-slate-200 dark:border-slate-700">
      <table className="w-full min-w-[980px] border-collapse text-xs">
        <thead><tr className="bg-slate-50 text-slate-500 dark:bg-slate-700/80 dark:text-slate-200"><th className="sticky left-0 z-20 w-44 border-b border-r bg-slate-50 p-3 text-left uppercase tracking-wide dark:border-slate-700 dark:bg-slate-700">Guardias</th>{weekDays.map(day=><th key={day.toISOString()} className={`min-w-28 border-b border-r p-3 text-center dark:border-slate-700 ${sameDay(day,new Date())?'bg-teal-50 text-teal-700 dark:bg-teal-900/40 dark:text-teal-100':''}`}><span className="block uppercase">{day.toLocaleDateString('es-CL',{weekday:'short'})}</span><span className="mt-1 block text-base text-slate-900 dark:text-slate-100">{day.getDate()}</span></th>)}</tr></thead>
        <tbody>{weekRows.map(row=><tr key={row.id}><th className="sticky left-0 z-10 border-b border-r bg-white p-3 text-left dark:border-slate-700 dark:bg-slate-800"><span className="block truncate font-bold text-slate-900 dark:text-slate-100">{row.nombre}</span><span className="mt-1 block truncate font-normal text-slate-400 dark:text-slate-300">{row.rango||'Guardia'}</span></th>{weekDays.map(day=>{const dayItems=visibleItems.filter(item=>(item.guardia_id===row.id||item.guardia_nombre===row.nombre||(!item.guardia_id&&!item.guardia_nombre&&row.id==='sin-guardia'))&&sameDay(new Date(item.fecha_hora_inicio),day));return <td key={day.toISOString()} className="border-b border-r p-1.5 align-top dark:border-slate-700">{dayItems.length?<div className="space-y-1">{dayItems.slice(0,3).map(item=><button key={item.id} onClick={()=>viewRoute(item)} disabled={tracking} className="block min-h-12 w-full rounded-lg border-l-4 border-teal-500 bg-teal-50 px-2 py-1.5 text-left text-[11px] font-semibold text-teal-800 transition hover:bg-teal-100 disabled:opacity-50 dark:bg-teal-900/30 dark:text-teal-100 dark:hover:bg-teal-900/50"><span className="block truncate">{new Date(item.fecha_hora_inicio).toLocaleTimeString('es-CL',{hour:'2-digit',minute:'2-digit'})} · {item.estado}</span><span className="mt-0.5 block truncate text-[10px] font-normal opacity-80">{item.recinto_nombre||'Sin recinto'}</span></button>)}{dayItems.length>3&&<span className="block px-1 text-[10px] font-bold text-slate-500 dark:text-slate-300">+{dayItems.length-3} más</span>}</div>:<div className="grid min-h-12 place-items-center rounded-lg border border-dashed border-slate-200 text-[11px] font-semibold text-slate-400 dark:border-slate-600 dark:text-slate-300">Libre</div>}</td>})}</tr>)}</tbody>
      </table>
      {!weekRows.length&&<div className="p-6 text-center text-sm text-slate-500 dark:text-slate-300">No hay guardias o rondas para esta semana.</div>}
    </div>}
    {periodView==='month'&&<div className="mt-4 overflow-hidden rounded-xl border border-slate-200 dark:border-slate-700"><div className="grid grid-cols-7 bg-slate-50 text-center text-xs font-bold uppercase text-slate-500 dark:bg-slate-800">{['Lun','Mar','Mié','Jue','Vie','Sáb','Dom'].map(day=><div key={day} className="p-2">{day}</div>)}</div><div className="grid grid-cols-7">{calendarDays.map(day=>{const dayItems=items.filter(item=>sameDay(new Date(item.fecha_hora_inicio),day));const incidents=dayItems.filter(item=>item.estado==='Incidente').length;const completed=dayItems.filter(item=>item.estado==='Completada').length;return <button key={day.toISOString()} onClick={()=>{setAnchorDate(day);setPeriodView('day')}} className={`min-h-20 border-t border-r border-slate-100 p-2 text-left transition hover:bg-teal-50 dark:border-slate-800 dark:hover:bg-teal-950/40 ${day.getMonth()!==anchorDate.getMonth()?'text-slate-300 dark:text-slate-600':''} ${sameDay(day,new Date())?'bg-teal-50/60 ring-1 ring-inset ring-teal-500':''}`}><span className="text-sm font-semibold">{day.getDate()}</span>{dayItems.length>0&&<div className="mt-2 space-y-1 text-[11px]"><p className="font-bold text-slate-700 dark:text-slate-200">{dayItems.length} rondas</p><div className="flex gap-1">{completed>0&&<span className="size-2 rounded-full bg-emerald-500" title={`${completed} completadas`}/>} {incidents>0&&<span className="size-2 rounded-full bg-red-500" title={`${incidents} incidentes`}/>} {dayItems.some(item=>item.estado==='En_curso')&&<span className="size-2 rounded-full bg-amber-500" title="En curso"/>}</div></div>}</button>})}</div></div>}
  </section>;

  return <><PageHead title="Rondas" subtitle="Patrullas, trazado GPS y novedades en terreno" action={canEdit?<Button variant="secondary" onClick={openNew} disabled={tracking||locating}><Plus size={18}/>Nueva ronda</Button>:undefined}/>{periodControls}{gpsMessage&&!open&&<p className={`mb-5 rounded-xl p-3 text-sm ${gpsMessage.includes('rechazado')||gpsMessage.includes('No fue')||gpsMessage.includes('No se pudo')||gpsMessage.includes('demasiado')?'bg-red-50 text-red-700':'bg-teal-50 text-teal-800 dark:bg-teal-950 dark:text-teal-200'}`}>{gpsMessage}</p>}<div className="grid gap-5 xl:grid-cols-[360px_1fr]"><section className="space-y-3">{visibleItems.map(item=><article key={item.id} className={`rounded-2xl border p-4 ${selected?.id===item.id?'border-teal-500 bg-teal-50 dark:bg-teal-950/40':'border-slate-200 bg-white dark:border-slate-800 dark:bg-slate-900'}`}><button onClick={()=>setSelected(item)} className="w-full text-left" disabled={tracking&&selected?.id!==item.id}><div className="flex justify-between gap-3"><b>{item.guardia_nombre}</b><Badge tone={toneFor(item.estado)}>{item.estado}</Badge></div><p className="mt-2 text-sm text-slate-500">{new Date(item.fecha_hora_inicio).toLocaleString('es-CL')}</p><p className="mt-1 text-sm">{Number(item.distancia_m||0).toFixed(0)} m recorridos · {routeOf(item.ruta).length} puntos GPS</p></button><div className="mt-3 flex gap-2"><Button variant="secondary" className="flex-1" onClick={()=>viewRoute(item)} disabled={tracking}><Eye size={17}/>Ver ronda y mapa</Button>{canDelete&&<Button variant="danger" onClick={async()=>{if(confirm('¿Eliminar esta ronda?')){await api('/ronda/'+item.id,{method:'DELETE'});await load()}}} disabled={tracking}><Trash2 size={17}/></Button>}</div></article>)}</section><section className="rounded-2xl border border-slate-200 bg-white p-4 dark:border-slate-800 dark:bg-slate-900"><div className="mb-4 flex items-center justify-between gap-4"><div><h2 className="font-bold">Trazado de la ronda</h2><p className="text-sm text-slate-500">{tracking?'Registrando y sincronizando la ubicación':'Selecciona una ronda y pulsa Ver ronda y mapa'}</p></div><LocateFixed className={tracking?'animate-pulse text-teal-600':'text-slate-400'}/></div><MapContainer center={shown[0]?[shown[0].lat,shown[0].lng]:[-33.4489,-70.6693]} zoom={15} scrollWheelZoom><FollowRoute points={shown}/><TileLayer attribution='&copy; OpenStreetMap' url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"/>{shown.length>0&&<><Polyline positions={shown.map(point=>[point.lat,point.lng])} color="#0d9488" weight={5}/><Marker position={[shown[0].lat,shown[0].lng]}><Popup>Inicio de ronda</Popup></Marker>{shown.length>1&&<Marker position={[shown[shown.length-1].lat,shown[shown.length-1].lng]}><Popup>{tracking?'Ubicación actual':'Fin de ronda'}</Popup></Marker>}</>}</MapContainer>{!shown.length&&<p className="mt-3 text-center text-sm text-slate-500">No hay puntos GPS registrados para esta ronda.</p>}</section></div><Dialog open={open} onClose={()=>{if(!tracking)setOpen(false)}} title="Nueva ronda GPS"><div className="grid gap-4 sm:grid-cols-2"><label className="text-sm font-semibold">Guardia<select value={draft.guardia_nombre||guardias[0]?.nombre||''} onChange={event=>setDraft({...draft,guardia_nombre:event.target.value})} disabled={!!createdInDialog} className="mt-1.5 w-full rounded-xl border border-slate-200 bg-white p-2.5 disabled:opacity-60 dark:border-slate-700 dark:bg-slate-900">{guardias.map(item=><option key={item.id}>{item.nombre}</option>)}</select></label><label className="text-sm font-semibold">Recinto<select value={draft.recinto_nombre||recintos[0]?.nombre||''} onChange={event=>setDraft({...draft,recinto_nombre:event.target.value})} disabled={!!createdInDialog} className="mt-1.5 w-full rounded-xl border border-slate-200 bg-white p-2.5 disabled:opacity-60 dark:border-slate-700 dark:bg-slate-900">{recintos.map(item=><option key={item.id}>{item.nombre}</option>)}</select></label><label className="text-sm font-semibold sm:col-span-2">Fecha y hora de inicio<input value={dialogStartedAt.toLocaleString('es-CL')} disabled className="mt-1.5 w-full rounded-xl border border-slate-200 bg-slate-100 p-2.5 text-slate-600 dark:border-slate-700 dark:bg-slate-800 dark:text-slate-300"/></label><label className="text-sm font-semibold sm:col-span-2">Novedades<textarea rows={3} value={draft.novedades} onChange={event=>setDraft({...draft,novedades:event.target.value})} disabled={!!createdInDialog} className="mt-1.5 w-full rounded-xl border border-slate-200 bg-transparent p-2.5 disabled:opacity-60 dark:border-slate-700"/></label></div>{gpsMessage&&<p className="mt-4 rounded-xl bg-teal-50 p-3 text-sm text-teal-800 dark:bg-teal-950 dark:text-teal-200">{gpsMessage}</p>}{(!guardias.length||!recintos.length)&&<p className="mt-3 text-sm text-amber-600">Debes tener al menos un guardia y un recinto activos.</p>}<div className="mt-6 flex justify-end gap-3">{!tracking&&<Button variant="secondary" onClick={()=>setOpen(false)} disabled={locating}>Cancelar</Button>}{tracking?<Button variant="danger" onClick={stop} disabled={locating}><Square size={17}/>{locating?'Validando GPS…':'Terminar ronda GPS'}</Button>:<Button onClick={createAndStart} disabled={locating||!!createdInDialog||!guardias.length||!recintos.length}><Play size={17}/>{locating?'Activando GPS…':'Iniciar ronda GPS'}</Button>}</div></Dialog></>;
}


