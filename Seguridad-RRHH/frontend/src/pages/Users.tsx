import { useEffect, useState } from 'react';
import { KeyRound, Pencil, Plus, Power, Trash2 } from 'lucide-react';
import { api, useAuth } from '../state';
import { Badge, Button, Dialog, PageHead } from '../components';

// Catálogo predeterminado; pueden agregarse nuevos módulos a esta lista.
const permissions = ['guardias','turnos','relevos','rondas','recintos','entradas','reportes','alertas','rrhh','usuarios','configuracion'];
const defaultGuardPermissions = new Set(['turnos','relevos','rondas','entradas','reportes','alertas']);
const protectedModules=[['turnos','Turnos'],['entradas','Entradas'],['reportes','Reportes'],['alertas','Alertas']] as const;
const roles = [['admin','Administrador'],['jefe_turno','Jefe de turno'],['guardia','Guardia']];
const rangos = [['supervisor','Supervisor'],['guardia_senior','Guardia senior'],['guardia','Guardia'],['cabo','Cabo'],['conserje','Conserje'],['nochero','Nochero']];
const blank = () => ({
  full_name:'', email:'', password:'', role:'guardia', rango:'guardia', telefono:'', cargo:'', enabled:true, send_invitation:false,
  permisos:{...Object.fromEntries(permissions.map(permission=>[permission,defaultGuardPermissions.has(permission)])),editar_turnos:false,eliminar_turnos:false,editar_entradas:true,editar_reportes:true,editar_alertas:true,eliminar_entradas:false,eliminar_reportes:false,eliminar_alertas:false,ver_registros:'propios'}
});

export default function Users(){
  const {user}=useAuth();
  const [items,setItems]=useState<any[]>([]);
  const [open,setOpen]=useState(false);
  const [editing,setEditing]=useState<any>(null);
  const [v,setV]=useState<any>(blank());
  const [error,setError]=useState('');
  const load=()=>api('/users').then(setItems);
  useEffect(()=>{load()},[]);
  const begin=(item?:any)=>{setEditing(item||null);setV(item?{...item,password:'',permisos:{...blank().permisos,...item.permisos}}:blank());setOpen(true)};
  const save=async(event:any)=>{event.preventDefault();setError('');try{if(editing)await api('/users/'+editing.id,{method:'PUT',body:JSON.stringify(v)});else await api('/users/invite',{method:'POST',body:JSON.stringify(v)});setOpen(false);load()}catch(reason){setError((reason as Error).message)}};
  const reset=async(item:any)=>{const password=prompt(`Nueva contraseña para ${item.email} (mínimo 8 caracteres):`);if(!password)return;try{await api(`/users/${item.id}/password`,{method:'PUT',body:JSON.stringify({password})});alert('Contraseña restablecida')}catch(reason){alert((reason as Error).message)}};
  const toggle=async(item:any)=>{await api('/users/'+item.id,{method:'PUT',body:JSON.stringify({enabled:!item.enabled})});load()};

  return <>
    <PageHead title="Usuarios" subtitle="Cuentas, contraseñas, roles y permisos" action={<Button onClick={()=>begin()}><Plus size={18}/>Crear usuario</Button>}/>
    <div className="overflow-hidden rounded-2xl border border-slate-200 bg-white dark:border-slate-800 dark:bg-slate-900">
      {items.map(item=><div key={item.id} className="grid gap-2 border-b border-slate-100 p-5 last:border-0 dark:border-slate-800 md:grid-cols-[1.4fr_1.5fr_1fr_1fr_auto] md:items-center">
        <div><b>{item.full_name}</b><p className="text-xs text-slate-500">{item.rango?.replace('_',' ')||'Sin rango'}</p></div><span className="text-sm text-slate-500">{item.email}</span><Badge>{item.role}</Badge><Badge tone={item.enabled?'green':'red'}>{item.enabled?'Habilitado':'Deshabilitado'}</Badge>
        <div className="flex gap-1"><Icon title="Editar" onClick={()=>begin(item)}><Pencil/></Icon><Icon title="Restablecer contraseña" onClick={()=>reset(item)}><KeyRound/></Icon><Icon title={item.enabled?'Deshabilitar':'Habilitar'} disabled={item.id===user?.id} onClick={()=>toggle(item)}><Power/></Icon><Icon title="Eliminar" disabled={item.id===user?.id} danger onClick={async()=>{if(confirm(`¿Eliminar definitivamente a ${item.full_name}?`)){await api('/users/'+item.id,{method:'DELETE'});load()}}}><Trash2/></Icon></div>
      </div>)}
    </div>
    <Dialog open={open} onClose={()=>setOpen(false)} title={editing?'Editar usuario':'Crear usuario'}>
      <form onSubmit={save} className="space-y-4">
        <div className="grid gap-4 sm:grid-cols-2"><Field label="Nombre completo" value={v.full_name} set={(value:string)=>setV({...v,full_name:value})} required/><Field label="Email" type="email" value={v.email} set={(value:string)=>setV({...v,email:value})} required/><Field label="Teléfono" value={v.telefono} set={(value:string)=>setV({...v,telefono:value})}/><Field label="Cargo" value={v.cargo} set={(value:string)=>setV({...v,cargo:value})}/>{!editing&&<Field label="Contraseña inicial" type="password" value={v.password} set={(value:string)=>setV({...v,password:value})} required/>}<Select label="Rol de acceso" value={v.role} options={roles} set={(value:string)=>setV({...v,role:value})}/><Select label="Rango operativo" value={v.rango} options={rangos} set={(value:string)=>setV({...v,rango:value})}/><label className="flex items-center gap-2 pt-7 text-sm font-semibold"><input type="checkbox" checked={v.enabled} onChange={event=>setV({...v,enabled:event.target.checked})}/>Usuario habilitado</label></div>
        <div className="rounded-xl bg-blue-50 p-3 text-sm text-blue-800 dark:bg-blue-950/40 dark:text-blue-200"><b>Rol:</b> controla el nivel de acceso al sistema. <b>Rango:</b> describe la jerarquía del personal; no entrega permisos por sí mismo.</div>
        <fieldset><legend className="mb-2 text-sm font-bold">Permisos por módulo</legend><div className="grid grid-cols-2 gap-2 sm:grid-cols-3">{permissions.map(key=><label key={key} className="flex items-center gap-2 rounded-lg bg-slate-50 p-2 text-sm capitalize dark:bg-slate-950"><input type="checkbox" checked={!!v.permisos?.[key]} onChange={event=>setV({...v,permisos:{...v.permisos,[key]:event.target.checked}})}/>{key}</label>)}</div></fieldset>
        <fieldset className="rounded-xl border border-slate-200 p-3 dark:border-slate-700"><legend className="px-1 text-sm font-bold">Acciones permitidas</legend><p className="mb-3 text-xs text-slate-500">Editar respeta el alcance de registros. Eliminar requiere autorización explícita.</p><div className="overflow-hidden rounded-lg border border-slate-200 dark:border-slate-700"><div className="grid grid-cols-[1fr_80px_80px] bg-slate-50 p-2 text-xs font-bold dark:bg-slate-800"><span>Módulo</span><span>Editar</span><span>Eliminar</span></div>{protectedModules.map(([key,label])=><div key={key} className="grid grid-cols-[1fr_80px_80px] items-center border-t border-slate-100 p-2 text-sm dark:border-slate-800"><span>{label}</span><input aria-label={`Editar ${label}`} type="checkbox" checked={v.permisos?.[`editar_${key}`]!==false} onChange={event=>setV({...v,permisos:{...v.permisos,[`editar_${key}`]:event.target.checked}})}/><input aria-label={`Eliminar ${label}`} type="checkbox" checked={v.permisos?.[`eliminar_${key}`]===true} onChange={event=>setV({...v,permisos:{...v.permisos,[`eliminar_${key}`]:event.target.checked}})}/></div>)}</div></fieldset>
        <fieldset className="rounded-xl border border-slate-200 p-3 dark:border-slate-700"><legend className="px-1 text-sm font-bold">Ver registros</legend><p className="mb-3 text-xs text-slate-500">Alcance aplicable a todos los módulos habilitados.</p><div className="grid gap-2 sm:grid-cols-2">{([['propios','Solo registros del usuario'],['todos','Ver todos los registros']] as const).map(([value,label])=><label key={value} className={`flex cursor-pointer items-center gap-2 rounded-lg border p-3 text-sm ${(v.permisos?.ver_registros||'propios')===value?'border-teal-500 bg-teal-50 dark:bg-teal-950/40':'border-slate-200 dark:border-slate-700'}`}><input type="radio" name="ver_registros" checked={(v.permisos?.ver_registros||'propios')===value} onChange={()=>setV({...v,permisos:{...v.permisos,ver_registros:value}})}/>{label}</label>)}</div></fieldset>
        {error&&<p className="text-sm text-red-600">{error}</p>}<Button className="w-full">{editing?'Guardar cambios':'Crear usuario'}</Button>
      </form>
    </Dialog>
  </>;
}

function Field({label,value,set,type='text',required=false}:any){return <label className="text-sm font-semibold">{label}<input type={type} value={value||''} onChange={event=>set(event.target.value)} minLength={type==='password'?8:undefined} required={required} className="mt-1.5 w-full rounded-xl border border-slate-200 bg-transparent p-2.5 dark:border-slate-700"/></label>}
function Select({label,value,options,set}:any){return <label className="text-sm font-semibold">{label}<select value={value||''} onChange={event=>set(event.target.value)} className="mt-1.5 w-full rounded-xl border border-slate-200 bg-white p-2.5 dark:border-slate-700 dark:bg-slate-900">{options.map(([id,name]:string[])=><option key={id} value={id}>{name}</option>)}</select></label>}
function Icon({children,danger,...props}:any){return <button type="button" {...props} className={`rounded-lg p-2 ${danger?'text-red-600':'text-slate-500'} hover:bg-slate-100 disabled:opacity-30 [&_svg]:size-4`}>{children}</button>}
