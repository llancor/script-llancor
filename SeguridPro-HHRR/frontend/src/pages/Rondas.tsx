import { useEffect, useMemo, useRef, useState } from 'react';
import { MapContainer, Marker, Polyline, Popup, TileLayer, useMap } from 'react-leaflet';
import { CalendarDays, ChevronLeft, ChevronRight, Eye, List, LocateFixed, Play, Plus, Square } from 'lucide-react';
import { api } from '../state';
import { modules } from '../config';
import { Badge, Button, Dialog, EntityForm, PageHead, toneFor } from '../components';

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
  const watch=useRef<number|undefined>(undefined);
  const routeRef=useRef<Point[]>([]);
  const lastSync=useRef(0);
  const trackingRef=useRef(false);

  const fields=useMemo(()=>modules.rondas.fields
    .filter(field=>!['guardia_id','recinto_id','distancia_m','fecha_hora_fin'].includes(field.name))
    .map(field=>field.name==='guardia_nombre'?{...field,type:'select' as const,options:guardias.map(guardia=>guardia.nombre)}:field.name==='recinto_nombre'?{...field,type:'select' as const,required:true,options:recintos.map(recinto=>recinto.nombre)}:field),[guardias,recintos]);

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
  const start=async()=>{
    if(!selected)return alert('Selecciona o crea una ronda');
    if(selected.estado==='Completada')return setGpsMessage('Esta ronda ya está completada. Crea o selecciona una ronda pendiente.');
    if(!window.isSecureContext)return setGpsMessage('El GPS requiere acceso mediante HTTPS. Abre GuardiaPro con un dominio seguro para iniciar el seguimiento.');
    if(!navigator.geolocation)return setGpsMessage('Este dispositivo o navegador no ofrece geolocalización.');
    if(tracking||locating)return;
    setLocating(true);setGpsMessage('Activando GPS y obteniendo la ubicación inicial…');
    try{
      const position=await readPosition();
      const initial=[...routeOf(selected.ruta),pointOf(position)];
      routeRef.current=initial;setRoute(initial);
      const updated=await api('/ronda/'+selected.id,{method:'PUT',body:JSON.stringify({estado:'En_curso',fecha_hora_inicio:new Date().toISOString(),fecha_hora_fin:null,ruta:initial,distancia_m:distanceOf(initial)})});
      setSelected(updated);
      setTracking(true);trackingRef.current=true;lastSync.current=0;
      setGpsMessage(`Ronda iniciada · GPS activo · precisión ${Math.round(position.coords.accuracy)} m`);
      watch.current=navigator.geolocation.watchPosition(position=>{
        const point=pointOf(position);
        const previous=routeRef.current[routeRef.current.length-1];
        if(previous&&hav(previous,point)<2)return;
        const next=[...routeRef.current,point];routeRef.current=next;setRoute(next);
        setGpsMessage(`GPS activo · precisión ${Math.round(position.coords.accuracy)} m · ${next.length} puntos`);
        if(Date.now()-lastSync.current>=10000){lastSync.current=Date.now();syncRoute(selected.id,next).catch(()=>setGpsMessage('GPS activo, pero no se pudo sincronizar el último avance.'))}
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
      setSelected(updated);setRoute([]);routeRef.current=[];setGpsMessage(`Ronda finalizada con ${points.length} puntos registrados.`);await load();
    }catch(error){setGpsMessage('No se pudo terminar la ronda sin una ubicación GPS válida. '+('code' in (error as object)?gpsError(error as GeolocationPositionError):(error as Error).message))}
    finally{setLocating(false)}
  };
  const viewRoute=(ronda:any)=>{setSelected(ronda);setRoute([]);routeRef.current=[];setGpsMessage(routeOf(ronda.ruta).length?'Ruta guardada cargada en el mapa.':'Esta ronda todavía no tiene puntos GPS.')};
  const shown=route.length?route:routeOf(selected?.ruta);
  const save=async(value:any)=>{const guardia=guardias.find(item=>item.nombre===(value.guardia_nombre||guardias[0]?.nombre));const recinto=recintos.find(item=>item.nombre===(value.recinto_nombre||recintos[0]?.nombre));if(!guardia||!recinto)throw new Error('Debes seleccionar un guardia y un recinto');const created=await api('/ronda',{method:'POST',body:JSON.stringify({...value,estado:value.estado||'Programada',guardia_id:guardia.id,guardia_nombre:guardia.nombre,recinto_id:recinto.id,recinto_nombre:recinto.nombre,ruta:[],distancia_m:0})});setSelected(created);setOpen(false);await load()};

  const range=useMemo(()=>{
    if(periodView==='day')return{start:startOfDay(anchorDate),end:addDays(startOfDay(anchorDate),1)};
    if(periodView==='week'){const start=weekStart(anchorDate);return{start,end:addDays(start,7)}}
    if(periodView==='month'){const start=new Date(anchorDate.getFullYear(),anchorDate.getMonth(),1);return{start,end:new Date(anchorDate.getFullYear(),anchorDate.getMonth()+1,1)}}
    return null;
  },[anchorDate,periodView]);
  const visibleItems=useMemo(()=>items.filter(item=>!range||((date=>date>=range.start&&date<range.end)(new Date(item.fecha_hora_inicio)))),[items,range]);
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
    {periodView==='month'&&<div className="mt-4 overflow-hidden rounded-xl border border-slate-200 dark:border-slate-700"><div className="grid grid-cols-7 bg-slate-50 text-center text-xs font-bold uppercase text-slate-500 dark:bg-slate-800">{['Lun','Mar','Mié','Jue','Vie','Sáb','Dom'].map(day=><div key={day} className="p-2">{day}</div>)}</div><div className="grid grid-cols-7">{calendarDays.map(day=>{const dayItems=items.filter(item=>sameDay(new Date(item.fecha_hora_inicio),day));const incidents=dayItems.filter(item=>item.estado==='Incidente').length;const completed=dayItems.filter(item=>item.estado==='Completada').length;return <button key={day.toISOString()} onClick={()=>{setAnchorDate(day);setPeriodView('day')}} className={`min-h-20 border-t border-r border-slate-100 p-2 text-left transition hover:bg-teal-50 dark:border-slate-800 dark:hover:bg-teal-950/40 ${day.getMonth()!==anchorDate.getMonth()?'text-slate-300 dark:text-slate-600':''} ${sameDay(day,new Date())?'bg-teal-50/60 ring-1 ring-inset ring-teal-500':''}`}><span className="text-sm font-semibold">{day.getDate()}</span>{dayItems.length>0&&<div className="mt-2 space-y-1 text-[11px]"><p className="font-bold text-slate-700 dark:text-slate-200">{dayItems.length} rondas</p><div className="flex gap-1">{completed>0&&<span className="size-2 rounded-full bg-emerald-500" title={`${completed} completadas`}/>} {incidents>0&&<span className="size-2 rounded-full bg-red-500" title={`${incidents} incidentes`}/>} {dayItems.some(item=>item.estado==='En_curso')&&<span className="size-2 rounded-full bg-amber-500" title="En curso"/>}</div></div>}</button>})}</div></div>}
  </section>;

  return <><PageHead title="Rondas" subtitle="Patrullas, trazado GPS y novedades en terreno" action={<div className="flex flex-wrap gap-2"><Button variant="secondary" onClick={()=>setOpen(true)} disabled={tracking||locating}><Plus size={18}/>Nueva ronda</Button>{tracking?<Button variant="danger" onClick={stop} disabled={locating}><Square size={17}/>{locating?'Validando GPS…':'Terminar ronda'}</Button>:<Button onClick={start} disabled={locating||selected?.estado==='Completada'}><Play size={17}/>{locating?'Activando GPS…':'Iniciar ronda'}</Button>}</div>}/>{periodControls}{gpsMessage&&<p className={`mb-5 rounded-xl p-3 text-sm ${gpsMessage.includes('rechazado')||gpsMessage.includes('No fue')||gpsMessage.includes('No se pudo')||gpsMessage.includes('demasiado')?'bg-red-50 text-red-700':'bg-teal-50 text-teal-800 dark:bg-teal-950 dark:text-teal-200'}`}>{gpsMessage}</p>}<div className="grid gap-5 xl:grid-cols-[360px_1fr]"><section className="space-y-3">{visibleItems.map(item=><article key={item.id} className={`rounded-2xl border p-4 ${selected?.id===item.id?'border-teal-500 bg-teal-50 dark:bg-teal-950/40':'border-slate-200 bg-white dark:border-slate-800 dark:bg-slate-900'}`}><button onClick={()=>setSelected(item)} className="w-full text-left" disabled={tracking&&selected?.id!==item.id}><div className="flex justify-between gap-3"><b>{item.guardia_nombre}</b><Badge tone={toneFor(item.estado)}>{item.estado}</Badge></div><p className="mt-2 text-sm text-slate-500">{new Date(item.fecha_hora_inicio).toLocaleString('es-CL')}</p><p className="mt-1 text-sm">{Number(item.distancia_m||0).toFixed(0)} m recorridos · {routeOf(item.ruta).length} puntos GPS</p></button><Button variant="secondary" className="mt-3 w-full" onClick={()=>viewRoute(item)} disabled={tracking}><Eye size={17}/>Ver ronda y mapa</Button></article>)}</section><section className="rounded-2xl border border-slate-200 bg-white p-4 dark:border-slate-800 dark:bg-slate-900"><div className="mb-4 flex items-center justify-between gap-4"><div><h2 className="font-bold">Trazado de la ronda</h2><p className="text-sm text-slate-500">{tracking?'Registrando y sincronizando la ubicación':'Selecciona una ronda y pulsa Ver ronda y mapa'}</p></div><LocateFixed className={tracking?'animate-pulse text-teal-600':'text-slate-400'}/></div><MapContainer center={shown[0]?[shown[0].lat,shown[0].lng]:[-33.4489,-70.6693]} zoom={15} scrollWheelZoom><FollowRoute points={shown}/><TileLayer attribution='&copy; OpenStreetMap' url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"/>{shown.length>0&&<><Polyline positions={shown.map(point=>[point.lat,point.lng])} color="#0d9488" weight={5}/><Marker position={[shown[0].lat,shown[0].lng]}><Popup>Inicio de ronda</Popup></Marker>{shown.length>1&&<Marker position={[shown[shown.length-1].lat,shown[shown.length-1].lng]}><Popup>{tracking?'Ubicación actual':'Fin de ronda'}</Popup></Marker>}</>}</MapContainer>{!shown.length&&<p className="mt-3 text-center text-sm text-slate-500">No hay puntos GPS registrados para esta ronda.</p>}</section></div><Dialog open={open} onClose={()=>setOpen(false)} title="Nueva ronda"><EntityForm fields={fields} onSave={save} onCancel={()=>setOpen(false)}/>{(!guardias.length||!recintos.length)&&<p className="mt-3 text-sm text-amber-600">Debes tener al menos un guardia y un recinto activos.</p>}</Dialog></>;
}
