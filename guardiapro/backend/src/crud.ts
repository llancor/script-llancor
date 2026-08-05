import { Router } from 'express';
import { db,sendEmail,sendTelegram } from './lib.js';
import { asyncHandler } from './middleware.js';
const allowed=['guardia','recinto','turno','ronda','entrada','reporte','alerta','relevo'] as const;
const dateFields:Record<string,string[]>= {guardia:['fecha_ingreso'],turno:['fecha'],ronda:['fecha_hora_inicio','fecha_hora_fin'],entrada:['hora_entrada','hora_salida'],reporte:['fecha'],alerta:['fecha'],relevo:['fecha_hora']};
const normalize=(model:string,body:any,updating=false)=>{
  const data:any=Object.fromEntries(Object.entries(body).map(([k,v])=>[k,dateFields[model]?.includes(k)&&v?new Date(v as string):v]));
  delete data.detalle_evento;
  delete data.detalle_horario;
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
async function notifyCreated(model:string,item:any){
  if(model!=='alerta'&&model!=='reporte')return;
  const config=await db.configuracion.findUnique({where:{id:1}});
  if(!config)return;
  const isAlert=model==='alerta';
  const label=isAlert?'Alerta':'Reporte';
  const details=[item.titulo,item.ubicacion&&`Ubicación: ${item.ubicacion}`,item.mensaje||item.descripcion].filter(Boolean).join('\n');
  const destination=config.notification_email||config.smtp_user||process.env.SMTP_USER;
  if((isAlert?config.alert_email_enabled:config.report_email_enabled)&&destination){
    await sendEmail(destination,`${label} GuardiaPro: ${item.titulo}`,details);
  }
  if(isAlert?config.alert_telegram_enabled:config.report_telegram_enabled){
    await sendTelegram(`<b>${label}: ${item.titulo}</b>\n${item.ubicacion||'Sin ubicación'}\n${item.mensaje||item.descripcion||''}`);
  }
}
crud.param('model',(req,res,next,model)=>allowed.includes(model)?next():res.status(404).json({message:'Recurso no encontrado'}));
crud.use('/:model',(req,res,next)=>{const permission=`${req.params.model}s`;if(req.user?.role==='admin'||req.user?.permisos?.[permission]===true)return next();return res.status(403).json({message:'No tienes permiso para acceder a este módulo'});});
crud.get('/:model',asyncHandler(async(req,res)=>{const model=req.params.model;const {q,page='1',limit='50',...filters}=req.query as any;const where:any={};for(const [k,v] of Object.entries(filters))if(v)where[k]=v;const searchable:Record<string,string[]>={guardia:['nombre','documento'],recinto:['nombre','direccion'],turno:['guardia_nombre','ubicacion'],ronda:['guardia_nombre','novedades'],entrada:['visitante_nombre','visitante_documento'],reporte:['titulo','descripcion'],alerta:['titulo','mensaje'],relevo:['guardia_saliente_nombre','guardia_entrante_nombre','novedades']};if(q)where.OR=searchable[model].map(f=>({[f]:{contains:q}}));const client=(db as any)[model];const [rows,total]=await Promise.all([client.findMany({where,orderBy:{created_at:'desc'},skip:(+page-1)*(+limit),take:+limit,...(model==='alerta'?{include:{guardia:{select:{nombre:true}}}}:{})}),client.count({where})]);const data=model==='alerta'?rows.map((item:any)=>({...item,guardia_nombre:item.guardia?.nombre||null})):rows;res.json({data,total,page:+page});}));
crud.get('/:model/:id',asyncHandler(async(req,res)=>res.json(await (db as any)[req.params.model].findUniqueOrThrow({where:{id:req.params.id}}))));
crud.post('/:model',asyncHandler(async(req,res)=>{if(req.params.model==='relevo'&&req.body.guardia_saliente_id===req.body.guardia_entrante_id)return res.status(400).json({message:'El guardia entrante debe ser diferente del guardia saliente'});const data=normalize(req.params.model,{...req.body,created_by_id:req.user!.id});const item=await (db as any)[req.params.model].create({data});req.app.get('io')?.emit(`${req.params.model}:created`,item);notifyCreated(req.params.model,item).catch(error=>console.error(`No se pudo notificar ${req.params.model}:`,error));res.status(201).json(item);}));
crud.put('/:model/:id',asyncHandler(async(req,res)=>{const data=normalize(req.params.model,req.body,true);delete data.id;delete data.created_at;delete data.updated_at;delete data.created_by_id;const item=await (db as any)[req.params.model].update({where:{id:req.params.id},data});req.app.get('io')?.emit(`${req.params.model}:updated`,item);res.json(item);}));
crud.delete('/:model/:id',asyncHandler(async(req,res)=>{await (db as any)[req.params.model].delete({where:{id:req.params.id}});res.status(204).end();}));
