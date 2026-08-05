import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { db,sendEmail,sendTelegram } from './lib.js';
import { asyncHandler } from './middleware.js';
const allowed=['guardia','recinto','turno','ronda','entrada','reporte','alerta','relevo'] as const;
const dateFields:Record<string,string[]>= {guardia:['fecha_ingreso'],turno:['fecha'],ronda:['fecha_hora_inicio','fecha_hora_fin'],entrada:['hora_entrada','hora_salida'],reporte:['fecha'],alerta:['fecha'],relevo:['fecha_hora']};
const normalize=(model:string,body:any,updating=false)=>{
  const data:any=Object.fromEntries(Object.entries(body).map(([k,v])=>[k,dateFields[model]?.includes(k)&&v?new Date(v as string):v]));
  delete data.detalle_evento;
  delete data.detalle_horario;
  delete data.crear_acceso;
  delete data.password_temporal;
  delete data.enviar_invitacion;
  if(!updating){
    const defaults:Record<string,Record<string,string>>={
      turno:{tipo_turno:'Manana',estado:'Programado'},
      ronda:{estado:'Programada'},
      entrada:{estado:'Dentro'},
      reporte:{tipo:'Novedad',severidad:'Baja',estado:'Abierto'},
      alerta:{tipo:'Intrusion',nivel:'Info',estado:'Activa'},
      guardia:{rango:'guardia',estado:'Activo'},
      recinto:{tipo:'Otro',estado:'Activo'}
    };
    for(const [field,value] of Object.entries(defaults[model]||{}))if(!data[field])data[field]=value;
  }
  const connect=(idField:string,relation:string)=>{
    if(!(idField in data))return;
    const id=data[idField];
    delete data[idField];
    if(id)data[relation]={connect:{id}};
    else if(updating)data[relation]={disconnect:true};
  };
  connect('guardia_id','guardia');
  if(model!=='relevo')connect('recinto_id','recinto');
  connect('created_by_id','creador');
  // Alerta obtiene el nombre mediante su relación con Guardia; no tiene una
  // columna guardia_nombre en el esquema actual.
  if(model==='alerta')delete data.guardia_nombre;
  return data;
};
export const crud=Router();
const canSeeAll=(req:any)=>req.user?.role==='admin'||req.user?.permisos?.ver_registros==='todos';
const protectedActions=['entrada','reporte','alerta'];
const canEdit=(req:any,model:string)=>req.user?.role==='admin'||!protectedActions.includes(model)||(req.user?.permisos?.[model+'s']===true&&req.user?.permisos?.[`editar_${model}s`]!==false);
const canDelete=(req:any,model:string)=>req.user?.role==='admin'||!protectedActions.includes(model)||req.user?.permisos?.[`eliminar_${model}s`]===true;
const ownedWhere=(req:any,model:string,forceOwn=false)=>{if(!forceOwn&&canSeeAll(req))return{};const creator={created_by_id:req.user!.id};const guardiaId=req.user?.guardia_id;if(!guardiaId)return creator;if(model==='guardia')return{OR:[creator,{id:guardiaId}]};if(model==='relevo')return{OR:[creator,{guardia_saliente_id:guardiaId},{guardia_entrante_id:guardiaId}]};if(['turno','ronda','entrada','reporte','alerta'].includes(model))return{OR:[creator,{guardia_id:guardiaId}]};return creator;};
async function ensureVisible(req:any,res:any,write=false){
  const item=await (db as any)[req.params.model].findFirst({where:{AND:[{id:req.params.id},ownedWhere(req,req.params.model,write&&req.user?.role==='guardia')]}});
  if(!item){res.status(404).json({message:'Registro no encontrado o fuera de tu alcance'});return null}
  return item;
}
async function notifyCreated(model:string,item:any){
  if(model!=='alerta'&&model!=='reporte')return;
  const config=await db.configuracion.findUnique({where:{id:1}});
  if(!config)return;
  const isAlert=model==='alerta';
  const label=isAlert?'Alerta':'Reporte';
  const guardia=item.guardia_nombre||(item.guardia_id
    ?(await db.guardia.findUnique({where:{id:item.guardia_id},select:{nombre:true}}))?.nombre
    :null)||'Sin guardia asignado';
  const recinto=item.recinto_nombre||'Sin recinto indicado';
  const locale=config.date_format==='MM/DD/YYYY'?'en-US':config.date_format==='YYYY-MM-DD'?'en-CA':'es-CL';
  const fechaHora=item.fecha?new Intl.DateTimeFormat(locale,{
    timeZone:config.timezone||'America/Santiago',
    day:'2-digit',month:'2-digit',year:'numeric',hour:'2-digit',minute:'2-digit',
    hour12:config.time_format==='12h'
  }).format(new Date(item.fecha)):'Sin fecha y hora';
  const lines=[item.titulo,`Tipo: ${item.tipo||'Sin tipo'}`,`Guardia: ${guardia}`,
    `Recinto: ${recinto}`,`Fecha y hora: ${fechaHora}`,
    `Ubicación: ${item.ubicacion||'Sin ubicación'}`,item.mensaje||item.descripcion].filter(Boolean);
  const details=lines.join('\n');
  const destination=config.notification_email||config.smtp_user||process.env.SMTP_USER;
  if((isAlert?config.alert_email_enabled:config.report_email_enabled)&&destination){
    await sendEmail(destination,`${label} GuardiaPro: ${item.titulo}`,details);
  }
  if(isAlert?config.alert_telegram_enabled:config.report_telegram_enabled){
    const escapeHtml=(value:unknown)=>String(value??'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
    await sendTelegram(`<b>${escapeHtml(label)}: ${escapeHtml(item.titulo)}</b>\n${lines.slice(1).map(escapeHtml).join('\n')}`);
  }
}
crud.param('model',(req,res,next,model)=>allowed.includes(model)?next():res.status(404).json({message:'Recurso no encontrado'}));
crud.use('/:model',(req,res,next)=>{const permission=`${req.params.model}s`;if(req.user?.role==='admin'||req.user?.permisos?.[permission]===true)return next();return res.status(403).json({message:'No tienes permiso para acceder a este módulo'});});
crud.get('/:model',asyncHandler(async(req,res)=>{const model=req.params.model;const {q,page='1',limit='50',...filters}=req.query as any;const requested:any={};for(const [k,v] of Object.entries(filters))if(v)requested[k]=v;const searchable:Record<string,string[]>={guardia:['nombre','documento'],recinto:['nombre','direccion'],turno:['guardia_nombre','ubicacion'],ronda:['guardia_nombre','novedades'],entrada:['visitante_nombre','visitante_documento'],reporte:['titulo','descripcion'],alerta:['titulo','mensaje'],relevo:['guardia_saliente_nombre','guardia_entrante_nombre','novedades']};if(q)requested.OR=searchable[model].map(f=>({[f]:{contains:q}}));const where={AND:[requested,ownedWhere(req,model)]};const client=(db as any)[model];const [rows,total]=await Promise.all([client.findMany({where,orderBy:{created_at:'desc'},skip:(+page-1)*(+limit),take:+limit,...(model==='alerta'?{include:{guardia:{select:{nombre:true}}}}:{})}),client.count({where})]);const data=model==='alerta'?rows.map((item:any)=>({...item,guardia_nombre:item.guardia?.nombre||null})):rows;res.json({data,total,page:+page});}));
crud.get('/:model/:id',asyncHandler(async(req,res)=>{const item=await ensureVisible(req,res);if(item)res.json(item)}));
crud.post('/:model',asyncHandler(async(req,res)=>{
  if(req.params.model==='relevo'&&req.body.guardia_saliente_id===req.body.guardia_entrante_id)return res.status(400).json({message:'El guardia entrante debe ser diferente del guardia saliente'});
  if(req.params.model==='guardia'&&req.body.crear_acceso){
    const email=String(req.body.email||'').trim().toLowerCase();const password=String(req.body.password_temporal||'');
    if(!email||!/^\S+@\S+\.\S+$/.test(email))return res.status(400).json({message:'Ingresa un correo válido para crear el acceso'});
    if(password.length<8)return res.status(400).json({message:'La contraseña temporal debe tener al menos 8 caracteres'});
    if(await db.user.findUnique({where:{email}}))return res.status(409).json({message:'Ya existe un usuario con este correo. Vincúlalo desde administración o utiliza otro correo'});
    const permisos={guardias:false,turnos:false,relevos:true,rondas:true,recintos:false,entradas:true,reportes:true,alertas:true,editar_entradas:true,editar_reportes:true,editar_alertas:true,eliminar_entradas:false,eliminar_reportes:false,eliminar_alertas:false,usuarios:false,configuracion:false,ver_registros:'propios'};
    const item=await db.$transaction(async transaction=>{
      const guardia=await transaction.guardia.create({data:normalize('guardia',{...req.body,email,created_by_id:req.user!.id})});
      await transaction.user.create({data:{full_name:guardia.nombre,email,password:await bcrypt.hash(password,12),role:'guardia',rango:guardia.rango,telefono:guardia.telefono,permisos,guardia_id:guardia.id,foto_url:guardia.foto_url,email_verified:true,enabled:true,must_change_password:true}});
      return guardia;
    });
    if(req.body.enviar_invitacion)sendEmail(email,'Acceso creado en GuardiaPro',`Hola ${item.nombre}. Tu cuenta fue creada. Usuario: ${email}\nContraseña temporal: ${password}\nPor seguridad deberás cambiarla al ingresar.`).catch(error=>console.error('No se pudo enviar la invitación:',error));
    req.app.get('io')?.emit('guardia:created',item);return res.status(201).json(item);
  }
  const data=normalize(req.params.model,{...req.body,created_by_id:req.user!.id});const item=await (db as any)[req.params.model].create({data});req.app.get('io')?.emit(`${req.params.model}:created`,item);notifyCreated(req.params.model,item).catch(error=>console.error(`No se pudo notificar ${req.params.model}:`,error));res.status(201).json(item);
}));
crud.put('/:model/:id',asyncHandler(async(req,res)=>{if(!canEdit(req,req.params.model))return res.status(403).json({message:'No tienes permiso para editar registros de este módulo'});if(!await ensureVisible(req,res,true))return;const input={...req.body};if(req.user?.role==='guardia'&&protectedActions.includes(req.params.model)){delete input.guardia_id;delete input.guardia_nombre}const data=normalize(req.params.model,input,true);delete data.id;delete data.created_at;delete data.updated_at;delete data.created_by_id;const item=await (db as any)[req.params.model].update({where:{id:req.params.id},data});if(req.params.model==='guardia')await db.user.updateMany({where:{guardia_id:item.id},data:{full_name:item.nombre,telefono:item.telefono,rango:item.rango,foto_url:item.foto_url}});req.app.get('io')?.emit(`${req.params.model}:updated`,item);res.json(item);}));
crud.delete('/:model/:id',asyncHandler(async(req,res)=>{if(!canDelete(req,req.params.model))return res.status(403).json({message:'No tienes permiso para eliminar registros de este módulo'});if(!await ensureVisible(req,res,true))return;await (db as any)[req.params.model].delete({where:{id:req.params.id}});res.status(204).end();}));
