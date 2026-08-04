import { useEffect, useMemo, useRef, useState } from 'react';
import { MapContainer, Marker, Polyline, Popup, TileLayer, useMap } from 'react-leaflet';
import { Eye, LocateFixed, Play, Plus, Square } from 'lucide-react';
import { api } from '../state';
import { modules } from '../config';
import { Badge, Button, Dialog, EntityForm, PageHead, toneFor } from '../components';

type Point={lat:number;lng:number;timestamp:string;accuracy?:number};
const hav=(a:Point,b:Point)=>{const R=6371000,dLat=(b.lat-a.lat)*Math.PI/180,dLng=(b.lng-a.lng)*Math.PI/180,x=Math.sin(dLat/2)**2+Math.cos(a.lat*Math.PI/180)*Math.cos(b.lat*Math.PI/180)*Math.sin(dLng/2)**2;return 2*R*Math.atan2(Math.sqrt(x),Math.sqrt(1-x))};
const distanceOf=(points:Point[])=>points.slice(1).reduce((total,point,index)=>total+hav(points[index],point),0);
const routeOf=(value:any):Point[]=>Array.isArray(value)?value.filter(point=>Number.isFinite(point?.lat)&&Number.isFinite(point?.lng)):[];

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
  const[route,setRoute]=useState<Point[]>([]);
  const[gpsMessage,setGpsMessage]=useState('');
  const watch=useRef<number|undefined>(undefined);
  const routeRef=useRef<Point[]>([]);
  const lastSync=useRef(0);
  const trackingRef=useRef(false);

  const fields=useMemo(()=>modules.rondas.fields
    .filter(field=>!['guardia_id','recinto_id','distancia_m','fecha_hora_fin'].includes(field.name))
    .map(field=>field.name==='guardia_nombre'?{...field,type:'select' as const,options:guardias.map(guardia=>guardia.nombre)}:field.name==='recinto_nombre'?{...field,type:'select' as const,required:true,options:recintos.map(recinto=>recinto.nombre)}:field),[guardias,recintos]);

  const load=async()=>{const response=await api('/ronda');setItems(response.data);setSelected((current:any)=>response.data.find((item:any)=>item.id===current?.id)||response.data[0])};
  useEffect(()=>{
    load();
    Promise.all([api('/lookups/guardias'),api('/lookups/recintos')]).then(([g,r])=>{setGuardias(g);setRecintos(r)});
    const refresh=window.setInterval(()=>{if(!trackingRef.current)load()},10000);
    return()=>{window.clearInterval(refresh);if(watch.current!==undefined)navigator.geolocation.clearWatch(watch.current)};
  },[]);

  const syncRoute=async(rondaId:string,points:Point[])=>api('/ronda/'+rondaId,{method:'PUT',body:JSON.stringify({ruta:points,distancia_m:distanceOf(points),estado:'En_curso'})});
  const start=async()=>{
    if(!selected)return alert('Selecciona o crea una ronda');
    if(!window.isSecureContext)return setGpsMessage('El GPS requiere acceso mediante HTTPS. Abre GuardiaPro con un dominio seguro para iniciar el seguimiento.');
    if(!navigator.geolocation)return setGpsMessage('Este dispositivo o navegador no ofrece geolocalización.');
    if(tracking)return;
    setGpsMessage('Solicitando permiso de ubicación…');
    const initial=routeOf(selected.ruta);
    routeRef.current=initial;
    setRoute(initial);
    try{
      const updated=await api('/ronda/'+selected.id,{method:'PUT',body:JSON.stringify({estado:'En_curso',fecha_hora_fin:null})});
      setSelected(updated);
      setTracking(true);trackingRef.current=true;lastSync.current=0;
      watch.current=navigator.geolocation.watchPosition(position=>{
        const point:Point={lat:position.coords.latitude,lng:position.coords.longitude,accuracy:position.coords.accuracy,timestamp:new Date().toISOString()};
        const previous=routeRef.current[routeRef.current.length-1];
        if(previous&&hav(previous,point)<2)return;
        const next=[...routeRef.current,point];routeRef.current=next;setRoute(next);
        setGpsMessage(`GPS activo · precisión ${Math.round(position.coords.accuracy)} m · ${next.length} puntos`);
        if(Date.now()-lastSync.current>=10000){lastSync.current=Date.now();syncRoute(selected.id,next).catch(()=>setGpsMessage('GPS activo, pero no se pudo sincronizar el último avance.'))}
      },error=>{
        const messages:Record<number,string>={1:'Permiso de ubicación rechazado. Habilita el GPS y autoriza este sitio.',2:'No fue posible obtener la ubicación del dispositivo.',3:'La ubicación tardó demasiado. Intenta en un lugar con mejor señal.'};
        setGpsMessage(messages[error.code]||error.message);
        if(error.code===1){setTracking(false);trackingRef.current=false}
      },{enableHighAccuracy:true,maximumAge:2000,timeout:15000});
    }catch(error){setGpsMessage((error as Error).message)}
  };
  const stop=async()=>{
    if(watch.current!==undefined){navigator.geolocation.clearWatch(watch.current);watch.current=undefined}
    setTracking(false);trackingRef.current=false;
    const points=routeRef.current;
    try{
      const updated=await api('/ronda/'+selected.id,{method:'PUT',body:JSON.stringify({ruta:points,distancia_m:distanceOf(points),fecha_hora_fin:new Date().toISOString(),estado:'Completada'})});
      setSelected(updated);setRoute([]);routeRef.current=[];setGpsMessage(`Ronda finalizada con ${points.length} puntos registrados.`);await load();
    }catch(error){setGpsMessage((error as Error).message)}
  };
  const viewRoute=(ronda:any)=>{setSelected(ronda);setRoute([]);routeRef.current=[];setGpsMessage(routeOf(ronda.ruta).length?'Ruta guardada cargada en el mapa.':'Esta ronda todavía no tiene puntos GPS.')};
  const shown=route.length?route:routeOf(selected?.ruta);
  const save=async(value:any)=>{const guardia=guardias.find(item=>item.nombre===(value.guardia_nombre||guardias[0]?.nombre));const recinto=recintos.find(item=>item.nombre===(value.recinto_nombre||recintos[0]?.nombre));if(!guardia||!recinto)throw new Error('Debes seleccionar un guardia y un recinto');const created=await api('/ronda',{method:'POST',body:JSON.stringify({...value,estado:value.estado||'Programada',guardia_id:guardia.id,guardia_nombre:guardia.nombre,recinto_id:recinto.id,recinto_nombre:recinto.nombre,ruta:[],distancia_m:0})});setSelected(created);setOpen(false);await load()};

  return <><PageHead title="Rondas" subtitle="Patrullas, trazado GPS y novedades en terreno" action={<div className="flex flex-wrap gap-2"><Button variant="secondary" onClick={()=>setOpen(true)} disabled={tracking}><Plus size={18}/>Nueva ronda</Button>{tracking?<Button variant="danger" onClick={stop}><Square size={17}/>Finalizar ronda</Button>:<Button onClick={start}><Play size={17}/>Iniciar GPS</Button>}</div>}/>{gpsMessage&&<p className={`mb-5 rounded-xl p-3 text-sm ${gpsMessage.includes('rechazado')||gpsMessage.includes('No fue')||gpsMessage.includes('demasiado')?'bg-red-50 text-red-700':'bg-teal-50 text-teal-800 dark:bg-teal-950 dark:text-teal-200'}`}>{gpsMessage}</p>}<div className="grid gap-5 xl:grid-cols-[360px_1fr]"><section className="space-y-3">{items.map(item=><article key={item.id} className={`rounded-2xl border p-4 ${selected?.id===item.id?'border-teal-500 bg-teal-50 dark:bg-teal-950/40':'border-slate-200 bg-white dark:border-slate-800 dark:bg-slate-900'}`}><button onClick={()=>setSelected(item)} className="w-full text-left" disabled={tracking&&selected?.id!==item.id}><div className="flex justify-between gap-3"><b>{item.guardia_nombre}</b><Badge tone={toneFor(item.estado)}>{item.estado}</Badge></div><p className="mt-2 text-sm text-slate-500">{new Date(item.fecha_hora_inicio).toLocaleString('es-CL')}</p><p className="mt-1 text-sm">{Number(item.distancia_m||0).toFixed(0)} m recorridos · {routeOf(item.ruta).length} puntos GPS</p></button><Button variant="secondary" className="mt-3 w-full" onClick={()=>viewRoute(item)} disabled={tracking}><Eye size={17}/>Ver ruta</Button></article>)}</section><section className="rounded-2xl border border-slate-200 bg-white p-4 dark:border-slate-800 dark:bg-slate-900"><div className="mb-4 flex items-center justify-between gap-4"><div><h2 className="font-bold">Trazado de la ronda</h2><p className="text-sm text-slate-500">{tracking?'Registrando y sincronizando la ubicación':'Selecciona una ronda y pulsa Ver ruta'}</p></div><LocateFixed className={tracking?'animate-pulse text-teal-600':'text-slate-400'}/></div><MapContainer center={shown[0]?[shown[0].lat,shown[0].lng]:[-33.4489,-70.6693]} zoom={15} scrollWheelZoom><FollowRoute points={shown}/><TileLayer attribution='&copy; OpenStreetMap' url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"/>{shown.length>0&&<><Polyline positions={shown.map(point=>[point.lat,point.lng])} color="#0d9488" weight={5}/><Marker position={[shown[0].lat,shown[0].lng]}><Popup>Inicio de ronda</Popup></Marker>{shown.length>1&&<Marker position={[shown[shown.length-1].lat,shown[shown.length-1].lng]}><Popup>{tracking?'Ubicación actual':'Fin de ronda'}</Popup></Marker>}</>}</MapContainer>{!shown.length&&<p className="mt-3 text-center text-sm text-slate-500">No hay puntos GPS registrados para esta ronda.</p>}</section></div><Dialog open={open} onClose={()=>setOpen(false)} title="Nueva ronda"><EntityForm fields={fields} onSave={save} onCancel={()=>setOpen(false)}/>{(!guardias.length||!recintos.length)&&<p className="mt-3 text-sm text-amber-600">Debes tener al menos un guardia y un recinto activos.</p>}</Dialog></>;
}
