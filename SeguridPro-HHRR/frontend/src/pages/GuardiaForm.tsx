import { useState } from 'react';
import { Camera, KeyRound, Trash2, UploadCloud } from 'lucide-react';
import type { Field } from '../config';
import { EntityForm } from '../components';
import { api } from '../state';

export default function GuardiaForm({fields,initial,onSave,onCancel}:{fields:Field[];initial?:any;onSave:(v:any)=>Promise<void>;onCancel:()=>void}){
  const [photo,setPhoto]=useState<string|null>(initial?.foto_url||null);
  const hasAccess=!!initial?.usuario;
  const [createAccess,setCreateAccess]=useState(!initial);
  const [password,setPassword]=useState('');
  const [sendInvitation,setSendInvitation]=useState(true);
  const upload=(file?:File)=>{if(!file)return;if(file.size>2_000_000)return alert('La fotografía no puede superar 2 MB');if(!file.type.startsWith('image/'))return alert('Selecciona un archivo de imagen');const reader=new FileReader();reader.onload=()=>setPhoto(String(reader.result));reader.readAsDataURL(file)};
  const save=async(value:any)=>{
    if(createAccess&&!value.email)throw new Error('El correo es obligatorio para crear el acceso a la plataforma');
    if(createAccess&&password.length<10)throw new Error('La contraseña temporal debe tener al menos 10 caracteres');
    await onSave({...value,foto_url:photo,crear_acceso:!initial&&createAccess,password_temporal:password,enviar_invitacion:sendInvitation});
    if(initial&&createAccess)await api(`/guardias/${initial.id}/activar-acceso`,{method:'POST',body:JSON.stringify({email:value.email,password,send_invitation:sendInvitation})});
  };
  return <>
    <section className="mb-5 rounded-xl border border-slate-200 p-4 dark:border-slate-700"><div className="mb-3 flex items-center gap-2"><Camera size={18} className="text-teal-600"/><div><b className="text-sm">Fotografía del guardia</b><p className="text-xs text-slate-500">Recomendado: 600 × 600 px, máximo 2 MB.</p></div></div><label className="group grid min-h-44 cursor-pointer place-items-center overflow-hidden rounded-xl border-2 border-dashed border-slate-300 bg-slate-50 hover:border-teal-500 dark:border-slate-700 dark:bg-slate-950">{photo?<img src={photo} alt="Fotografía del guardia" className="size-40 rounded-xl object-cover p-1"/>:<span className="flex flex-col items-center gap-2 text-slate-500 group-hover:text-teal-600"><UploadCloud size={32}/><b className="text-sm">Subir fotografía</b><span className="text-xs">PNG, JPG o WebP</span></span>}<input className="sr-only" type="file" accept="image/png,image/jpeg,image/webp" onChange={event=>upload(event.target.files?.[0])}/></label>{photo&&<button type="button" onClick={()=>setPhoto(null)} className="mt-3 inline-flex items-center gap-1.5 text-xs font-semibold text-red-600"><Trash2 size={14}/>Quitar fotografía</button>}</section>
    {!hasAccess&&<section className="mb-5 rounded-xl border border-teal-200 bg-teal-50/60 p-4 dark:border-teal-900 dark:bg-teal-950/30">
      <label className="flex items-center gap-3 font-bold"><input type="checkbox" checked={createAccess} onChange={event=>setCreateAccess(event.target.checked)}/><KeyRound size={18} className="text-teal-600"/>{initial?'Activar perfil para la web':'Crear acceso a la plataforma'}</label>
      {createAccess&&<div className="mt-4 space-y-3"><p className="text-xs text-slate-600 dark:text-slate-300">Se creará una cuenta vinculada con rol Guardia, permisos predeterminados y acceso solamente a sus registros.</p><label className="block text-sm font-semibold">Contraseña temporal<input type="password" minLength={10} required value={password} onChange={event=>setPassword(event.target.value)} className="mt-1.5 w-full rounded-xl border border-slate-200 bg-white p-2.5 dark:border-slate-700 dark:bg-slate-900"/></label><label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={sendInvitation} onChange={event=>setSendInvitation(event.target.checked)}/>Enviar los datos de acceso por correo</label><p className="text-xs text-amber-700 dark:text-amber-300">El guardia deberá cambiar esta contraseña al iniciar sesión.</p></div>}
    </section>}
    <EntityForm fields={fields.filter(field=>field.name!=='foto_url')} initial={initial} onSave={save} onCancel={onCancel}/>
  </>;
}
