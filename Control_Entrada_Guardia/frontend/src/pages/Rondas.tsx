import { useEffect, useMemo, useRef, useState } from 'react';
import { MapContainer, Marker, Polyline, Popup, TileLayer } from 'react-leaflet';
import { LocateFixed, Play, Plus, Square } from 'lucide-react';
import { api } from '../state';
import { modules } from '../config';
import { Badge, Button, Dialog, EntityForm, PageHead, toneFor } from '../components';

type Point={lat:number;lng:number;timestamp:string};
const hav=(a:Point,b:Point)=>{const R=6371000,dLat=(b.lat-a.lat)*Math.PI/180,dLng=(b.lng-a.lng)*Math.PI/180,x=Math.sin(dLat/2)**2+Math.cos(a.lat*Math.PI/180)*Math.cos(b.lat*Math.PI/180)*Math.sin(dLng/2)**2;return 2*R*Math.atan2(Math.sqrt(x),Math.sqrt(1-x))};

export default function Rondas(){
  const[items,setItems]=useState<any[]>([]);
  const[guardias,setGuardias]=useState<any[]>([]);
  const[recintos,setRecintos]=useState<any[]>([]);
  const[selected,setSelected]=useState<any>();
  const[open,setOpen]=useState(false);
  const[tracking,setTracking]=useState(false);
  const[route,setRoute]=useState<Point[]>([]);
  const watch=useRef<number|undefined>(undefined);
  const fields=useMemo(()=>modules.rondas.fields
    .filter(f=>!['guardia_id','recinto_id'].includes(f.name))
    .map(f=>f.name==='guardia_nombre'?{...f,type:'select' as const,options:guardias.map(g=>g.nombre)}:f.name==='recinto_nombre'?{...f,type:'select' as const,required:true,options:recintos.map(r=>r.nombre)}:f),[guardias,recintos]);
  const load=()=>api('/ronda').then(r=>{setItems(r.data);if(!selected&&r.data[0])setSelected(r.data[0])});
  useEffect(()=>{load();Promise.all([api('/lookups/guardias'),api('/lookups/recintos')]).then(([g,r])=>{setGuardias(g);setRecintos(r)});return()=>{if(watch.current!==undefined)navigator.geolocation.clearWatch(watch.current)}},[]);
  const start=()=>{if(!selected)return alert('Selecciona o crea una ronda');setTracking(true);watch.current=navigator.geolocation.watchPosition(p=>setRoute(r=>[...r,{lat:p.coords.latitude,lng:p.coords.longitude,timestamp:new Date().toISOString()}]),e=>alert(e.message),{enableHighAccuracy:true,maximumAge:3000})};
  const stop=async()=>{if(watch.current!==undefined)navigator.geolocation.clearWatch(watch.current);setTracking(false);const distance=route.slice(1).reduce((n,p,i)=>n+hav(route[i],p),0);await api('/ronda/'+selected.id,{method:'PUT',body:JSON.stringify({ruta:route,distancia_m:distance,fecha_hora_fin:new Date().toISOString(),estado:'Completada'})});setRoute([]);load()};
  const shown=route.length?route:(selected?.ruta||[]);
  const save=async(v:any)=>{const guardia=guardias.find(g=>g.nombre===(v.guardia_nombre||guardias[0]?.nombre));const recinto=recintos.find(r=>r.nombre===(v.recinto_nombre||recintos[0]?.nombre));if(!guardia||!recinto)throw new Error('Debes seleccionar un guardia y un recinto');const created=await api('/ronda',{method:'POST',body:JSON.stringify({...v,guardia_id:guardia.id,guardia_nombre:guardia.nombre,recinto_id:recinto.id,recinto_nombre:recinto.nombre,ruta:[]})});setSelected(created);setOpen(false);load()};
  return <><PageHead title="Rondas" subtitle="Patrullas, trazado GPS y novedades en terreno" action={<div className="flex gap-2"><Button variant="secondary" onClick={()=>setOpen(true)}><Plus size={18}/>Nueva ronda</Button>{tracking?<Button variant="danger" onClick={stop}><Square size={17}/>Finalizar</Button>:<Button onClick={start}><Play size={17}/>Iniciar GPS</Button>}</div>}/><div className="grid gap-5 xl:grid-cols-[360px_1fr]"><section className="space-y-3">{items.map(x=><button key={x.id} onClick={()=>setSelected(x)} className={`w-full rounded-2xl border p-4 text-left ${selected?.id===x.id?'border-teal-500 bg-teal-50 dark:bg-teal-950/40':'border-slate-200 bg-white dark:border-slate-800 dark:bg-slate-900'}`}><div className="flex justify-between gap-3"><b>{x.guardia_nombre}</b><Badge tone={toneFor(x.estado)}>{x.estado}</Badge></div><p className="mt-2 text-sm text-slate-500">{new Date(x.fecha_hora_inicio).toLocaleString('es-CL')}</p><p className="mt-1 text-sm">{Number(x.distancia_m||0).toFixed(0)} m recorridos</p></button>)}</section><section className="rounded-2xl border border-slate-200 bg-white p-4 dark:border-slate-800 dark:bg-slate-900"><div className="mb-4 flex items-center justify-between"><div><h2 className="font-bold">Trazado de la ronda</h2><p className="text-sm text-slate-500">{tracking?'Registrando ubicación en tiempo real':'Selecciona una ronda para ver su ruta'}</p></div><LocateFixed className={tracking?'animate-pulse text-teal-600':'text-slate-400'}/></div><MapContainer center={shown[0]?[shown[0].lat,shown[0].lng]:[-33.4489,-70.6693]} zoom={15} scrollWheelZoom><TileLayer attribution='&copy; OpenStreetMap' url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"/>{shown.length>0&&<><Polyline positions={shown.map((p:Point)=>[p.lat,p.lng])} color="#0d9488" weight={5}/><Marker position={[shown[0].lat,shown[0].lng]}><Popup>Inicio de ronda</Popup></Marker></>}</MapContainer></section></div><Dialog open={open} onClose={()=>setOpen(false)} title="Nueva ronda"><EntityForm fields={fields} onSave={save} onCancel={()=>setOpen(false)}/>{(!guardias.length||!recintos.length)&&<p className="mt-3 text-sm text-amber-600">Debes tener al menos un guardia y un recinto activos.</p>}</Dialog></>;
}
