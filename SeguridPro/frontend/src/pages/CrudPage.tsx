import { useEffect, useMemo, useState } from 'react';
import { CalendarDays, ChevronLeft, ChevronRight, List } from 'lucide-react';
import { api, useAuth } from '../state';
import { modules } from '../config';
import { Badge, Button, Dialog, EntityForm as BaseEntityForm, PageHead, Pencil, Plus, Search, Trash2, toneFor } from '../components';
import GuardiaForm from './GuardiaForm';
import{formatDateTime}from'../date-format';

type PeriodView='day'|'week'|'month'|'list';
const calendarModules:Record<string,string>={turnos:'fecha',entradas:'hora_entrada',reportes:'fecha',alertas:'fecha'};
const startOfDay=(value:Date)=>new Date(value.getFullYear(),value.getMonth(),value.getDate());
const addDays=(value:Date,days:number)=>{const date=new Date(value);date.setDate(date.getDate()+days);return date};
const sameDay=(a:Date,b:Date)=>a.getFullYear()===b.getFullYear()&&a.getMonth()===b.getMonth()&&a.getDate()===b.getDate();
const weekStart=(value:Date)=>addDays(startOfDay(value),-((value.getDay()+6)%7));
const entrySchedule=(item:any)=>`Entrada: ${formatDateTime(item.hora_entrada)} · Salida: ${item.hora_salida?formatDateTime(item.hora_salida):'Pendiente'}`;
const eventDetails=(item:any)=>`Fecha y hora: ${formatDateTime(item.fecha)} · Tipo: ${String(item.tipo||'Sin tipo').replaceAll('_',' ')}`;

export default function CrudPage({moduleKey}:{moduleKey:string}){
  const{user}=useAuth();
  const m=modules[moduleKey];
  const EntityForm=m.key==='guardia'?GuardiaForm:BaseEntityForm;
  const[items,setItems]=useState<any[]>([]);
  const[recintos,setRecintos]=useState<any[]>([]);
  const[guardias,setGuardias]=useState<any[]>([]);
  const[q,setQ]=useState('');
  const[editing,setEditing]=useState<any>();
  const[open,setOpen]=useState(false);
  const[error,setError]=useState('');
  const[periodView,setPeriodView]=useState<PeriodView>('week');
  const[anchorDate,setAnchorDate]=useState(()=>startOfDay(new Date()));
  const dateField=calendarModules[moduleKey];
  const usesGuardia=m.fields.some(f=>f.name==='guardia_nombre');
  const usesRecinto=m.fields.some(f=>f.name==='recinto_nombre');
  const protectedModule=['entradas','reportes','alertas'].includes(moduleKey);
  const hasEditPermission=user?.role==='admin'||!protectedModule||(user?.permisos?.[moduleKey]===true&&user?.permisos?.[`editar_${moduleKey}`]!==false);
  const hasDeletePermission=user?.role==='admin'||!protectedModule||user?.permisos?.[`eliminar_${moduleKey}`]===true;
  const isOwn=(item:any)=>user?.role!=='guardia'||item.created_by_id===user?.id||!!user?.guardia_id&&item.guardia_id===user.guardia_id;
  const canEdit=(item:any)=>hasEditPermission&&isOwn(item);
  const canDelete=(item:any)=>hasDeletePermission&&isOwn(item);
  const fields=useMemo(()=>m.fields
    .filter(f=>!['guardia_id','recinto_id'].includes(f.name)&&!(editing&&user?.role==='guardia'&&protectedModule&&f.name==='guardia_nombre'))
    .map(f=>f.name==='recinto_nombre'?{...f,type:'select' as const,options:recintos.map(r=>r.nombre)}:f.name==='guardia_nombre'?{...f,type:'select' as const,options:guardias.map(g=>g.nombre)}:f),[m,recintos,guardias,editing,user?.role,protectedModule]);
  const load=()=>api(`/${m.key}?limit=500&q=${encodeURIComponent(q)}`).then(r=>setItems(r.data.map((item:any)=>m.key==='entrada'?{...item,detalle_horario:entrySchedule(item)}:['reporte','alerta'].includes(m.key)?{...item,detalle_evento:eventDetails(item)}:item))).catch(e=>setError(e.message));
  useEffect(()=>{const t=setTimeout(load,250);return()=>clearTimeout(t)},[moduleKey,q]);
  useEffect(()=>{setGuardias([]);setRecintos([]);if(usesGuardia)api('/lookups/guardias').then(setGuardias).catch(e=>setError(e.message));if(usesRecinto)api('/lookups/recintos').then(setRecintos).catch(e=>setError(e.message))},[moduleKey]);
  const save=async(v:any)=>{
    const data={...v};
    delete data.detalle_evento;
    delete data.detalle_horario;
    if(usesGuardia){const guardia=guardias.find(g=>g.nombre===(data.guardia_nombre||guardias[0]?.nombre));data.guardia_id=guardia?.id||null;data.guardia_nombre=guardia?.nombre||null}
    if(usesRecinto){const recinto=recintos.find(r=>r.nombre===(data.recinto_nombre||recintos[0]?.nombre));data.recinto_id=recinto?.id||null;data.recinto_nombre=recinto?.nombre||null}
    await api(`/${m.key}${editing?'/'+editing.id:''}`,{method:editing?'PUT':'POST',body:JSON.stringify(data)});
    setOpen(false);setEditing(undefined);load();
  };
  const del=async(x:any)=>{if(!confirm(`¿Eliminar ${m.singular} “${x[m.primary]}”? Esta acción no se puede deshacer.`))return;await api(`/${m.key}/${x.id}`,{method:'DELETE'});load()};

  const range=useMemo(()=>{
    if(!dateField||periodView==='list')return null;
    if(periodView==='day')return{start:startOfDay(anchorDate),end:addDays(startOfDay(anchorDate),1)};
    if(periodView==='week'){const start=weekStart(anchorDate);return{start,end:addDays(start,7)}}
    const start=new Date(anchorDate.getFullYear(),anchorDate.getMonth(),1);
    return{start,end:new Date(anchorDate.getFullYear(),anchorDate.getMonth()+1,1)};
  },[anchorDate,dateField,periodView]);
  const visibleItems=useMemo(()=>items.filter(item=>!range||((date=>!Number.isNaN(date.getTime())&&date>=range.start&&date<range.end)(new Date(item[dateField])))),[items,range,dateField]);
  const periodLabel=!dateField?'':periodView==='list'?`Todos los ${m.title.toLowerCase()}`:periodView==='day'?anchorDate.toLocaleDateString('es-CL',{weekday:'long',day:'numeric',month:'long'}):periodView==='week'?`${range!.start.toLocaleDateString('es-CL',{day:'numeric',month:'short'})} – ${addDays(range!.end,-1).toLocaleDateString('es-CL',{day:'numeric',month:'short',year:'numeric'})}`:anchorDate.toLocaleDateString('es-CL',{month:'long',year:'numeric'});
  const movePeriod=(direction:number)=>setAnchorDate(current=>periodView==='day'?addDays(current,direction):periodView==='week'?addDays(current,direction*7):new Date(current.getFullYear(),current.getMonth()+direction,1));
  const monthStart=new Date(anchorDate.getFullYear(),anchorDate.getMonth(),1);
  const calendarStart=addDays(monthStart,-((monthStart.getDay()+6)%7));
  const calendarDays=Array.from({length:42},(_,index)=>addDays(calendarStart,index));
  const periodControls=dateField&&<section className="mb-5 rounded-2xl border border-slate-200 bg-white p-4 shadow-sm dark:border-slate-800 dark:bg-slate-900">
    <div className="flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
      <div className="flex flex-wrap gap-2">{([['day','Día'],['week','Semana'],['month','Mes'],['list','Lista']] as [PeriodView,string][]).map(([value,label])=><button key={value} onClick={()=>setPeriodView(value)} className={`inline-flex items-center gap-2 rounded-xl px-3 py-2 text-sm font-semibold transition ${periodView===value?'bg-teal-600 text-white':'bg-slate-100 text-slate-600 hover:bg-slate-200 dark:bg-slate-800 dark:text-slate-200'}`}>{value==='month'?<CalendarDays size={16}/>:value==='list'?<List size={16}/>:null}{label}</button>)}</div>
      <div className="flex items-center justify-between gap-2 lg:justify-end"><button onClick={()=>movePeriod(-1)} disabled={periodView==='list'} className="rounded-lg p-2 hover:bg-slate-100 disabled:opacity-30 dark:hover:bg-slate-800" aria-label="Periodo anterior"><ChevronLeft size={20}/></button><button onClick={()=>setAnchorDate(startOfDay(new Date()))} className="rounded-lg px-3 py-2 text-sm font-semibold hover:bg-slate-100 dark:hover:bg-slate-800">Hoy</button><button onClick={()=>movePeriod(1)} disabled={periodView==='list'} className="rounded-lg p-2 hover:bg-slate-100 disabled:opacity-30 dark:hover:bg-slate-800" aria-label="Periodo siguiente"><ChevronRight size={20}/></button></div>
    </div>
    <div className="mt-4 flex flex-wrap items-center justify-between gap-2"><h2 className="font-bold capitalize text-slate-800 dark:text-white">{periodLabel}</h2><span className="rounded-full bg-teal-50 px-3 py-1 text-sm font-semibold text-teal-700 dark:bg-teal-950 dark:text-teal-200">{visibleItems.length} {visibleItems.length===1?m.singular:m.title.toLowerCase()}</span></div>
    {periodView==='month'&&<div className="mt-4 overflow-hidden rounded-xl border border-slate-200 dark:border-slate-700"><div className="grid grid-cols-7 bg-slate-50 text-center text-xs font-bold uppercase text-slate-500 dark:bg-slate-800">{['Lun','Mar','Mié','Jue','Vie','Sáb','Dom'].map(day=><div key={day} className="p-2">{day}</div>)}</div><div className="grid grid-cols-7">{calendarDays.map(day=>{const count=items.filter(item=>sameDay(new Date(item[dateField]),day)).length;return <button key={day.toISOString()} onClick={()=>{setAnchorDate(day);setPeriodView('day')}} className={`min-h-20 border-t border-r border-slate-100 p-2 text-left transition hover:bg-teal-50 dark:border-slate-800 dark:hover:bg-teal-950/40 ${day.getMonth()!==anchorDate.getMonth()?'text-slate-300 dark:text-slate-600':''} ${sameDay(day,new Date())?'bg-teal-50/60 ring-1 ring-inset ring-teal-500':''}`}><span className="text-sm font-semibold">{day.getDate()}</span>{count>0&&<p className="mt-2 text-[11px] font-bold text-slate-700 dark:text-slate-200">{count} {count===1?m.singular:m.title.toLowerCase()}</p>}</button>})}</div></div>}
  </section>;

  return <><PageHead title={m.title} subtitle={m.subtitle} action={<Button onClick={()=>{setEditing(undefined);setOpen(true)}}><Plus size={18}/>Nuevo {m.singular}</Button>}/>{periodControls}<div className="relative mb-5 max-w-md"><Search className="absolute left-3 top-3 text-slate-400" size={19}/><input value={q} onChange={e=>setQ(e.target.value)} placeholder={`Buscar en ${m.title.toLowerCase()}…`} className="w-full rounded-xl border border-slate-200 bg-white py-2.5 pl-10 pr-3 dark:border-slate-700 dark:bg-slate-900"/></div>{error&&<p className="mb-4 text-red-600">{error}</p>}<div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">{visibleItems.map(x=><article key={x.id} className="rounded-2xl border border-slate-200/80 bg-white p-5 shadow-sm dark:border-slate-800 dark:bg-slate-900"><div className="flex items-start justify-between gap-3"><div className="min-w-0"><h3 className="truncate font-bold">{x[m.primary]}</h3><p className="mt-1 truncate text-sm text-slate-500">{x[m.secondary!]||'Sin información adicional'}</p>{x.guardia_nombre&&<p className="mt-2 text-xs font-semibold">{x.guardia_nombre}</p>}{x.recinto_nombre&&<p className="mt-1 text-xs font-semibold text-teal-700">{x.recinto_nombre}</p>}</div>{m.status&&<Badge tone={toneFor(x[m.status])}>{x[m.status]}</Badge>}</div>{(canEdit(x)||canDelete(x))&&<div className="mt-5 flex gap-2 border-t border-slate-100 pt-4 dark:border-slate-800">{canEdit(x)&&<Button variant="secondary" className="flex-1" onClick={()=>{setEditing(x);setOpen(true)}}><Pencil size={16}/>Editar</Button>}{canDelete(x)&&<button onClick={()=>del(x)} aria-label={`Eliminar ${m.singular}`} className="rounded-xl p-2.5 text-slate-400 hover:bg-red-50 hover:text-red-600"><Trash2 size={18}/></button>}</div>}</article>)}</div>{!visibleItems.length&&!error&&<div className="rounded-2xl border border-dashed border-slate-300 p-12 text-center text-slate-500">{items.length?'No hay registros en el período seleccionado.':'No hay registros. Crea el primero para comenzar.'}</div>}<Dialog open={open} onClose={()=>setOpen(false)} title={`${editing?'Editar':'Nuevo'} ${m.singular}`}><EntityForm fields={fields} initial={editing} onSave={save} onCancel={()=>setOpen(false)}/>{((usesGuardia&&!guardias.length)||(usesRecinto&&!recintos.length))&&<p className="mt-3 text-sm text-amber-600">Debes crear y activar los guardias o recintos necesarios antes de continuar.</p>}</Dialog></>;
}
