import { useEffect,useState } from 'react';
import { Building2,KeyRound,Pencil,Plus,Power,Trash2 } from 'lucide-react';
import { api } from '../state';
import { Badge,Button,Dialog,PageHead } from '../components';

const moduleNames=['guardias','turnos','relevos','rondas','recintos','entradas','reportes','alertas','rrhh','usuarios','configuracion'];
const blank=()=>({
  nombre:'',slug:'',rut:'',email:'',telefono:'',estado:'Activa',vence_at:'',limite_usuarios:'',limite_guardias:'',limite_recintos:'',
  modulos:Object.fromEntries(moduleNames.map(name=>[name,true])),admin:{full_name:'',email:'',password:''}
});

export default function Empresas(){
  const[items,setItems]=useState<any[]>([]);
  const[open,setOpen]=useState(false);
  const[editing,setEditing]=useState<any>(null);
  const[value,setValue]=useState<any>(blank());
  const[admins,setAdmins]=useState<any[]>([]);
  const[adminId,setAdminId]=useState('');
  const[adminPassword,setAdminPassword]=useState('');
  const[error,setError]=useState('');
  const load=()=>api('/empresas').then(setItems);
  useEffect(()=>{load()},[]);
  const begin=async(item?:any)=>{setEditing(item||null);setAdmins([]);setAdminId('');setAdminPassword('');setError('');setValue(item?{...blank(),...item,vence_at:item.vence_at?.slice(0,10)||'',modulos:{...blank().modulos,...item.modulos}}:blank());setOpen(true);if(item){try{const detail=await api('/empresas/'+item.id);setAdmins(detail.users||[]);setAdminId(detail.users?.[0]?.id||'')}catch(reason){setError((reason as Error).message)}}};
  const save=async(event:any)=>{event.preventDefault();setError('');try{const data={...value,limite_usuarios:value.limite_usuarios?Number(value.limite_usuarios):null,limite_guardias:value.limite_guardias?Number(value.limite_guardias):null,limite_recintos:value.limite_recintos?Number(value.limite_recintos):null,vence_at:value.vence_at||null};if(editing){delete data.admin;await api('/empresas/'+editing.id,{method:'PUT',body:JSON.stringify(data)})}else await api('/empresas',{method:'POST',body:JSON.stringify(data)});setOpen(false);load()}catch(reason){setError((reason as Error).message)}};
  const set=(key:string,next:any)=>setValue({...value,[key]:next});
  const resetAdminPassword=async()=>{setError('');if(!adminId)return setError('La empresa no tiene un administrador disponible');if(adminPassword.length<10)return setError('La contraseña temporal debe tener al menos 10 caracteres');try{const result=await api(`/empresas/${editing.id}/admin-password`,{method:'PUT',body:JSON.stringify({user_id:adminId,password:adminPassword})});setAdminPassword('');alert(result.message)}catch(reason){setError((reason as Error).message)}};
  return <>
    <PageHead title="Empresas" subtitle="Clientes, módulos, límites y vigencia" action={<Button onClick={()=>begin()}><Plus size={18}/>Nueva empresa</Button>}/>
    <div className="grid gap-4 lg:grid-cols-2">{items.map(item=><article key={item.id} className="rounded-2xl border border-slate-200 bg-white p-5 dark:border-slate-800 dark:bg-slate-900">
      <div className="flex items-start justify-between"><div className="flex gap-3"><span className="grid size-11 place-items-center rounded-xl bg-teal-50 text-teal-700"><Building2/></span><div><h3 className="font-bold">{item.nombre}</h3><p className="text-xs text-slate-500">{item.slug} · {item.email||'Sin email'}</p></div></div><Badge tone={item.estado==='Activa'?'green':'red'}>{item.estado}</Badge></div>
      <div className="my-4 grid grid-cols-3 gap-2 text-center text-sm"><Stat n={item.limite_usuarios||'∞'} label="Límite usuarios"/><Stat n={item.limite_guardias||'∞'} label="Límite guardias"/><Stat n={item.vence_at?new Date(item.vence_at).toLocaleDateString('es-CL'):'Sin fecha'} label="Vencimiento"/></div>
      <p className="text-xs text-slate-500">Módulos: {Object.entries(item.modulos||{}).filter(entry=>entry[1]).map(entry=>entry[0]).join(', ')||'Ninguno'}</p>
      <div className="mt-4 flex justify-end gap-1"><Icon title="Editar" onClick={()=>begin(item)}><Pencil/></Icon><Icon title={item.estado==='Activa'?'Suspender':'Activar'} onClick={async()=>{await api('/empresas/'+item.id,{method:'PUT',body:JSON.stringify({estado:item.estado==='Activa'?'Suspendida':'Activa'})});load()}}><Power/></Icon><Icon title="Eliminar" danger onClick={async()=>{if(confirm('¿Eliminar lógicamente esta empresa?')){await api('/empresas/'+item.id,{method:'DELETE'});load()}}}><Trash2/></Icon></div>
    </article>)}</div>
    <Dialog open={open} onClose={()=>setOpen(false)} title={editing?'Editar empresa':'Crear empresa'}><form onSubmit={save} className="space-y-4">
      <div className="grid gap-3 sm:grid-cols-2"><Field label="Nombre" value={value.nombre} set={(next:string)=>{setValue({...value,nombre:next,slug:editing?value.slug:next.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g,'').replace(/[^a-z0-9]+/g,'-').replace(/^-|-$/g,'')})}} required/><Field label="Identificador" value={value.slug} set={(next:string)=>set('slug',next)} required/><Field label="RUT" value={value.rut} set={(next:string)=>set('rut',next)}/><Field label="Email comercial" type="email" value={value.email} set={(next:string)=>set('email',next)}/><Field label="Teléfono" value={value.telefono} set={(next:string)=>set('telefono',next)}/><Field label="Vencimiento" type="date" value={value.vence_at} set={(next:string)=>set('vence_at',next)}/><Field label="Límite usuarios" type="number" value={value.limite_usuarios} set={(next:string)=>set('limite_usuarios',next)}/><Field label="Límite guardias" type="number" value={value.limite_guardias} set={(next:string)=>set('limite_guardias',next)}/></div>
      <fieldset><legend className="mb-2 text-sm font-bold">Módulos contratados</legend><div className="grid grid-cols-2 gap-2 sm:grid-cols-3">{moduleNames.map(name=><label key={name} className="rounded-lg bg-slate-50 p-2 text-sm capitalize dark:bg-slate-950"><input className="mr-2" type="checkbox" checked={!!value.modulos[name]} onChange={event=>set('modulos',{...value.modulos,[name]:event.target.checked})}/>{name}</label>)}</div></fieldset>
      {!editing&&<fieldset className="rounded-xl border p-3 dark:border-slate-700"><legend className="px-1 text-sm font-bold">Primer administrador</legend><div className="grid gap-3 sm:grid-cols-2"><Field label="Nombre" value={value.admin.full_name} set={(next:string)=>set('admin',{...value.admin,full_name:next})} required/><Field label="Email" type="email" value={value.admin.email} set={(next:string)=>set('admin',{...value.admin,email:next})} required/><Field label="Contraseña temporal" type="password" value={value.admin.password} set={(next:string)=>set('admin',{...value.admin,password:next})} required/></div></fieldset>}
      {editing&&<fieldset className="rounded-xl border border-amber-200 p-3 dark:border-amber-900"><legend className="flex items-center gap-2 px-1 text-sm font-bold"><KeyRound size={16}/>Restablecer acceso administrativo</legend><p className="mb-3 text-xs text-slate-500">Solo se muestran administradores de la empresa. Al restablecer, se cerrarán sus sesiones y deberá cambiar la contraseña al ingresar.</p><div className="grid gap-3 sm:grid-cols-2"><label className="text-sm font-semibold">Administrador<select value={adminId} onChange={event=>setAdminId(event.target.value)} required className="mt-1.5 w-full rounded-xl border border-slate-200 bg-white p-2.5 dark:border-slate-700 dark:bg-slate-900"><option value="">Seleccionar</option>{admins.map(admin=><option key={admin.id} value={admin.id}>{admin.full_name} · {admin.email}</option>)}</select></label><Field label="Nueva contraseña temporal" type="password" value={adminPassword} set={setAdminPassword}/></div><Button type="button" variant="secondary" className="mt-3" onClick={resetAdminPassword} disabled={!adminId||adminPassword.length<10}><KeyRound size={16}/>Restablecer contraseña</Button></fieldset>}
      {error&&<p className="text-sm text-red-600">{error}</p>}<Button className="w-full">Guardar</Button>
    </form></Dialog>
  </>;
}
function Stat({n,label}:{n:string|number;label:string}){return <div className="rounded-xl bg-slate-50 p-2 dark:bg-slate-950"><b className="block">{n}</b><span className="text-xs text-slate-500">{label}</span></div>}
function Field({label,value,set,type='text',required=false}:any){return <label className="text-sm font-semibold">{label}<input className="mt-1.5 w-full rounded-xl border border-slate-200 bg-transparent p-2.5 dark:border-slate-700" type={type} value={value||''} minLength={type==='password'?10:undefined} required={required} onChange={event=>set(event.target.value)}/></label>}
function Icon({children,danger,...props}:any){return <button type="button" {...props} className={`rounded-lg p-2 ${danger?'text-red-600':'text-slate-500'} hover:bg-slate-100 [&_svg]:size-4`}>{children}</button>}
