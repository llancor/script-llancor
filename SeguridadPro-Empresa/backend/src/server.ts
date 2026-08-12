import 'dotenv/config';
import express from 'express'; import cors from 'cors'; import helmet from 'helmet'; import morgan from 'morgan';
import { createServer } from 'http'; import { Server } from 'socket.io'; import rateLimit from 'express-rate-limit'; import bcrypt from 'bcryptjs';
import authRoutes from './auth.js'; import { crud } from './crud.js'; import { auth,admin,permit,asyncHandler,superadmin } from './middleware.js'; import { audit,db,encryptSecret,publicUser,sendEmail,sendTelegram } from './lib.js';
import { testNextcloud } from './nextcloud.js';
import { databaseAdmin } from './database-admin.js';
import { processRrhhNotifications,rrhh } from './rrhh.js';
import { validateShifts } from './shift-rules.js';
import { empresas } from './empresas.js';
import { miEmpresa } from './mi-empresa.js';
const app=express();const server=createServer(app);const io=new Server(server,{cors:{origin:process.env.FRONTEND_URL}});app.set('io',io);
app.use(helmet());app.use(cors({origin:process.env.FRONTEND_URL}));app.use(express.json({limit:'50mb'}));app.use(morgan('dev'));app.use('/api/auth',rateLimit({windowMs:60_000,limit:30}),authRoutes);
app.get('/api/health',(req,res)=>res.json({status:'ok'}));
app.get('/api/public/branding',asyncHandler(async(req,res)=>{const c=await db.configuracion.upsert({where:{id:1},update:{},create:{id:1}});res.json({timezone:c.timezone,date_format:c.date_format,time_format:c.time_format,theme:c.theme,brand_name:c.brand_name,brand_subtitle:c.brand_subtitle,hero_title:c.hero_title,hero_description:c.hero_description,hero_footer:c.hero_footer,logo_url:c.logo_url,icon_url:c.icon_url,hero_image_url:c.hero_image_url});}));
app.get('/api/dashboard',auth,asyncHandler(async(req,res)=>{
  if(req.user?.role==='superadmin')return res.status(403).json({message:'El propietario de la plataforma no tiene acceso a informaciÃ³n operativa privada de las empresas'});
  const start=new Date();start.setHours(0,0,0,0);const end=new Date(start);end.setDate(end.getDate()+1);
  const tenant=req.user?.empresa_id?{empresa_id:req.user.empresa_id}:{};const all=['admin','superadmin'].includes(req.user?.role||'')||req.user?.permisos?.ver_registros==='todos';const scope=(model:string):any=>{if(all)return tenant;const creator={created_by_id:req.user!.id};const guardiaId=req.user?.guardia_id;if(!guardiaId)return{AND:[tenant,creator]};if(model==='guardia')return{AND:[tenant,{OR:[creator,{id:guardiaId}]}]};return{AND:[tenant,{OR:[creator,{guardia_id:guardiaId}]}]}};
  const [guardias,turnos,alertas,entradas,reportes,rondas,alertasLista,turnosLista]=await Promise.all([
    db.guardia.count({where:{AND:[scope('guardia'),{estado:'Activo'}]}}),db.turno.count({where:{AND:[scope('turno'),{fecha:{gte:start,lt:end}}]}}),db.alerta.count({where:{AND:[scope('alerta'),{estado:'Activa'}]}}),db.entrada.count({where:{AND:[scope('entrada'),{estado:'Dentro'}]}}),db.reporte.count({where:{AND:[scope('reporte'),{estado:'Abierto'}]}}),db.ronda.findMany({where:scope('ronda'),take:5,orderBy:{fecha_hora_inicio:'desc'}}),db.alerta.findMany({where:{AND:[scope('alerta'),{estado:'Activa'}]},take:5,orderBy:{fecha:'desc'}}),db.turno.findMany({where:{AND:[scope('turno'),{fecha:{gte:start,lt:end}}]},take:5,orderBy:{hora_inicio:'asc'}})
  ]);
  res.json({stats:{guardias,turnos,alertas,entradas,reportes,rondas:rondas.length},rondas,alertasLista,turnosLista});
}));
app.get('/api/lookups/recintos',auth,asyncHandler(async(req,res)=>res.json(await db.recinto.findMany({where:{estado:'Activo',...(req.user!.empresa_id?{empresa_id:req.user!.empresa_id}:{})},select:{id:true,nombre:true,direccion:true},orderBy:{nombre:'asc'}}))));
app.get('/api/lookups/guardias',auth,asyncHandler(async(req,res)=>{const limited=!['admin','superadmin'].includes(req.user?.role||'')&&req.user?.permisos?.ver_registros!=='todos'&&req.user?.guardia_id;res.json(await db.guardia.findMany({where:{estado:'Activo',...(req.user!.empresa_id?{empresa_id:req.user!.empresa_id}:{}),...(limited?{id:req.user!.guardia_id}:{})},select:{id:true,nombre:true,documento:true,recinto_id:true,recinto_nombre:true},orderBy:{nombre:'asc'}}))}));
app.use('/api/users',auth,asyncHandler(async(req,res,next)=>{if(req.user!.role!=='superadmin'&&req.method!=='GET'){if(['POST','PUT','PATCH'].includes(req.method)){req.body??={};req.body.empresa_id=req.user!.empresa_id;if(req.body.role==='superadmin')req.body.role='admin'}if(req.method==='POST'&&req.path==='/invite'){const company=await db.empresa.findUniqueOrThrow({where:{id:req.user!.empresa_id!}});if(company.limite_usuarios&&await db.user.count({where:{empresa_id:company.id,enabled:true}})>=company.limite_usuarios)return res.status(409).json({message:'La empresa alcanzÃ³ el lÃ­mite de usuarios activos contratado. Deshabilita o elimina una cuenta antes de crear otra.'})}}next()}));
app.get('/api/users',auth,admin,asyncHandler(async(req,res)=>res.json((await db.user.findMany({where:req.user!.role==='superadmin'?{}:{empresa_id:req.user!.empresa_id},orderBy:{created_at:'desc'}})).map(publicUser))));
app.use('/api/empresas',auth,empresas);
app.use('/api/mi-empresa',auth,miEmpresa);
app.get('/api/audit',auth,admin,asyncHandler(async(req,res)=>{const limit=Math.min(500,Math.max(1,Number(req.query.limit||100)));res.json(await db.auditLog.findMany({take:limit,orderBy:{created_at:'desc'},include:{user:{select:{full_name:true,email:true}}}}))}));
app.post('/api/users/invite',auth,admin,asyncHandler(async(req,res)=>{const {password,send_invitation,...data}=req.body;if(!password||password.length<8)return res.status(400).json({message:'La contraseÃ±a debe tener al menos 8 caracteres'});const user=await db.user.create({data:{...data,password:await bcrypt.hash(password,12),email_verified:true,enabled:data.enabled??true,must_change_password:true}});if(send_invitation)await sendEmail(user.email,'Cuenta creada en Seguridad-RRHH',`Tu cuenta fue creada. Ingresa con ${user.email} y la contraseÃ±a proporcionada por el administrador. DeberÃ¡s cambiarla al ingresar.`);res.status(201).json(publicUser(user));}));
app.put('/api/users/:id',auth,admin,asyncHandler(async(req,res)=>{const current=await db.user.findFirst({where:{id:req.params.id,...(req.user!.role==='superadmin'?{}:{empresa_id:req.user!.empresa_id})}});if(!current)return res.status(404).json({message:'Usuario no encontrado en esta empresa'});const allowed=['full_name','email','role','rango','telefono','cargo','permisos','enabled'];const data:any=Object.fromEntries(Object.entries(req.body).filter(([key])=>allowed.includes(key)));if(data.enabled===true&&!current.enabled&&current.empresa_id){const company=await db.empresa.findUniqueOrThrow({where:{id:current.empresa_id}});if(company.limite_usuarios&&await db.user.count({where:{empresa_id:current.empresa_id,enabled:true}})>=company.limite_usuarios)return res.status(409).json({message:'No puedes habilitar esta cuenta: la empresa alcanzÃ³ el lÃ­mite de usuarios activos'})}res.json(publicUser(await db.user.update({where:{id:current.id},data})));}));
app.put('/api/users/:id/password',auth,admin,asyncHandler(async(req,res)=>{const {password}=req.body;if(!password||password.length<8)return res.status(400).json({message:'La contraseÃ±a debe tener al menos 8 caracteres'});await db.user.update({where:{id:req.params.id},data:{password:await bcrypt.hash(password,12),email_verified:true,must_change_password:true}});res.json({message:'ContraseÃ±a restablecida. El usuario deberÃ¡ cambiarla al ingresar'});}));
app.post('/api/guardias/:id/activar-acceso',auth,admin,asyncHandler(async(req,res)=>{const guard=await db.guardia.findUniqueOrThrow({where:{id:req.params.id},include:{usuario:true}});if(guard.usuario){if(!guard.usuario.enabled){await db.user.update({where:{id:guard.usuario.id},data:{enabled:true}});return res.json({message:'Acceso web reactivado correctamente'})}return res.status(409).json({message:'Este guardia ya tiene un perfil web activo'});}const email=String(req.body.email||guard.email||'').trim().toLowerCase(),password=String(req.body.password||'');if(!/^\S+@\S+\.\S+$/.test(email))return res.status(400).json({message:'El guardia necesita un correo vÃ¡lido'});if(password.length<10)return res.status(400).json({message:'La contraseÃ±a temporal debe tener al menos 10 caracteres'});if(await db.user.findUnique({where:{email}}))return res.status(409).json({message:'Ya existe otro usuario con ese correo'});const permisos={guardias:false,turnos:false,relevos:true,rondas:true,recintos:false,entradas:true,reportes:true,alertas:true,rrhh:false,usuarios:false,configuracion:false,editar_entradas:true,editar_reportes:true,editar_alertas:true,eliminar_entradas:false,eliminar_reportes:false,eliminar_alertas:false,ver_registros:'propios'};const user=await db.user.create({data:{full_name:guard.nombre,email,password:await bcrypt.hash(password,12),role:'guardia',rango:guard.rango,telefono:guard.telefono,permisos,guardia_id:guard.id,foto_url:guard.foto_url,email_verified:true,enabled:true,must_change_password:true}});if(req.body.send_invitation)sendEmail(email,'Acceso activado en Seguridad',`Hola ${guard.nombre}. Tu acceso fue activado. Usuario: ${email}\nContraseÃ±a temporal: ${password}\nDeberÃ¡s cambiarla al ingresar.`).catch(console.error);await audit('activar_acceso_guardia',{userId:req.user!.id,entity:'guardia',entityId:guard.id,detail:{usuario:user.id},ip:req.ip,userAgent:req.get('user-agent')});res.status(201).json({message:'Perfil web creado y activado correctamente',user:publicUser(user)});}));
app.delete('/api/users/:id',auth,admin,asyncHandler(async(req,res)=>{
  if(req.params.id===req.user!.id)return res.status(400).json({message:'No puedes eliminar tu usuario desde administraciÃ³n'});
  const current=await db.user.findFirst({where:{id:req.params.id,...(req.user!.role==='superadmin'?{}:{empresa_id:req.user!.empresa_id})}});
  if(!current)return res.status(404).json({message:'Usuario no encontrado en esta empresa'});
  await db.$transaction(async tx=>{
    await Promise.all([
      tx.guardia.updateMany({where:{created_by_id:current.id},data:{created_by_id:null}}),tx.recinto.updateMany({where:{created_by_id:current.id},data:{created_by_id:null}}),
      tx.turno.updateMany({where:{created_by_id:current.id},data:{created_by_id:null}}),tx.ronda.updateMany({where:{created_by_id:current.id},data:{created_by_id:null}}),
      tx.entrada.updateMany({where:{created_by_id:current.id},data:{created_by_id:null}}),tx.reporte.updateMany({where:{created_by_id:current.id},data:{created_by_id:null}}),
      tx.alerta.updateMany({where:{created_by_id:current.id},data:{created_by_id:null}}),tx.relevo.updateMany({where:{created_by_id:current.id},data:{created_by_id:null}}),
      tx.trabajador.updateMany({where:{created_by_id:current.id},data:{created_by_id:null}}),tx.eventoRRHH.updateMany({where:{created_by_id:current.id},data:{created_by_id:null}}),
      tx.amonestacion.updateMany({where:{created_by_id:current.id},data:{created_by_id:null}}),tx.auditLog.updateMany({where:{user_id:current.id},data:{user_id:null}}),
      tx.trabajador.updateMany({where:{user_id:current.id},data:{user_id:null}}),tx.session.deleteMany({where:{user_id:current.id}})
    ]);
    await tx.user.delete({where:{id:current.id}});
  });
  await audit('eliminar_usuario',{userId:req.user!.id,entity:'usuario',entityId:current.id,detail:{email:current.email},ip:req.ip,userAgent:req.get('user-agent')});
  res.status(204).end();
}));
const safeConfig=(c:any)=>({...c,smtp_password:undefined,telegram_bot_token:undefined,nextcloud_password:undefined,smtp_password_configured:!!c.smtp_password,telegram_token_configured:!!c.telegram_bot_token,nextcloud_password_configured:!!c.nextcloud_password});
app.get('/api/config',auth,superadmin,asyncHandler(async(req,res)=>res.json(safeConfig(await db.configuracion.upsert({where:{id:1},update:{},create:{id:1}})))));app.put('/api/config',auth,superadmin,asyncHandler(async(req,res)=>{const allowed=['login_max_attempts','login_lock_minutes','login_ban_email_enabled','login_ban_telegram_enabled','nextcloud_enabled','nextcloud_url','nextcloud_user','nextcloud_password','nextcloud_folder','smtp_host','smtp_port','smtp_secure','smtp_user','smtp_password','mail_from','telegram_enabled','telegram_bot_token','telegram_chat_id','alert_email_enabled','alert_telegram_enabled','report_email_enabled','report_telegram_enabled','notification_email','shift_email_enabled','timezone','date_format','time_format','turno_dia_inicio','turno_dia_fin','turno_manana_inicio','turno_manana_fin','turno_tarde_inicio','turno_tarde_fin','turno_noche_inicio','turno_noche_fin','turno_dia_color','turno_noche_color','turno_personalizado_color','theme','brand_name','brand_subtitle','hero_title','hero_description','hero_footer','logo_url','icon_url','hero_image_url'];const data:any=Object.fromEntries(Object.entries(req.body).filter(([key])=>allowed.includes(key)));if('login_max_attempts'in data)data.login_max_attempts=Math.min(20,Math.max(1,Number(data.login_max_attempts)||5));if('login_lock_minutes'in data)data.login_lock_minutes=Math.min(1440,Math.max(1,Number(data.login_lock_minutes)||15));if(!data.smtp_password)delete data.smtp_password;if(!data.telegram_bot_token)delete data.telegram_bot_token;if(data.nextcloud_password)data.nextcloud_password=encryptSecret(String(data.nextcloud_password));else delete data.nextcloud_password;const config=await db.configuracion.upsert({where:{id:1},update:data,create:{id:1,...data}});res.json(safeConfig(config));}));
app.post('/api/config/test-email',auth,superadmin,asyncHandler(async(req,res)=>{if(!req.body.email)return res.status(400).json({message:'Indica un email de destino'});await sendEmail(req.body.email,'Prueba SMTP Seguridad-RRHH','La configuraciÃ³n SMTP funciona correctamente.');res.json({message:'Correo de prueba enviado'});}));
app.post('/api/config/test-telegram',auth,superadmin,asyncHandler(async(req,res)=>{await sendTelegram('La configuraciÃ³n de Telegram funciona correctamente.');res.json({message:'Mensaje de prueba enviado'});}));
app.post('/api/config/test-nextcloud',auth,superadmin,asyncHandler(async(req,res)=>{await testNextcloud();res.json({message:'ConexiÃ³n con Nextcloud correcta'});}));
app.post('/api/turnos/programar',auth,permit('turnos'),asyncHandler(async(req,res)=>{
  const {guardia_id,guardia_nombre,recinto_id,recinto_nombre,tipo_turno,fecha,hora_inicio,hora_fin,ubicacion,observaciones,periodo='dia'}=req.body;
  if(!guardia_id||!guardia_nombre||!fecha||!hora_inicio||!hora_fin)return res.status(400).json({message:'Guardia, fecha y horario son obligatorios'});
  if(!['Manana','Tarde','Dia','Noche','Personalizado'].includes(tipo_turno))return res.status(400).json({message:'Tipo de turno invÃ¡lido'});
  if(hora_inicio===hora_fin)return res.status(400).json({message:'La hora de inicio y tÃ©rmino deben ser diferentes'});
  const start=new Date(`${fecha}T00:00:00.000Z`);if(Number.isNaN(start.getTime()))return res.status(400).json({message:'Fecha invÃ¡lida'});
  const dates:Date[]=[];const cursor=new Date(start);const total=periodo==='semana'?7:periodo==='mes'?new Date(start.getUTCFullYear(),start.getUTCMonth()+1,0).getUTCDate()-start.getUTCDate()+1:1;
  for(let index=0;index<total;index++){dates.push(new Date(cursor));cursor.setUTCDate(cursor.getUTCDate()+1)}
  await validateShifts(guardia_id,dates.map(day=>({fecha:day,hora_inicio,hora_fin})));
  await db.turno.createMany({data:dates.map(day=>({empresa_id:req.user!.empresa_id!,guardia_id,guardia_nombre,recinto_id:recinto_id||null,recinto_nombre:recinto_nombre||null,tipo_turno,fecha:day,hora_inicio,hora_fin,ubicacion:ubicacion||null,observaciones:observaciones||null,estado:'Programado',created_by_id:req.user!.id}))});
  const [guardia,config]=await Promise.all([db.guardia.findUnique({where:{id:guardia_id},select:{email:true}}),db.configuracion.findUnique({where:{id:1}})]);
  if(config?.shift_email_enabled&&guardia?.email)sendEmail(guardia.email,`ProgramaciÃ³n de turnos Seguridad-RRHH`,`${guardia_nombre}: ${dates.length} turno(s) desde ${fecha}, horario ${hora_inicio} a ${hora_fin}, ${recinto_nombre||ubicacion||'sin recinto indicado'}.`).catch(error=>console.error('No se pudo enviar programaciÃ³n:',error));
  res.status(201).json({message:`Se crearon ${dates.length} turno(s)`,count:dates.length});
}));
app.post('/api/turnos/copiar-semana',auth,permit('turnos'),asyncHandler(async(req,res)=>{const{fecha_origen,fecha_destino}=req.body;if(!fecha_origen||!fecha_destino)return res.status(400).json({message:'Indica semana de origen y destino'});const origin=new Date(`${fecha_origen}T00:00:00.000Z`),target=new Date(`${fecha_destino}T00:00:00.000Z`),end=new Date(origin);end.setUTCDate(end.getUTCDate()+7);const source=await db.turno.findMany({where:{fecha:{gte:origin,lt:end},estado:{not:'Cancelado'}}});if(!source.length)return res.status(404).json({message:'La semana de origen no tiene turnos'});const offset=target.getTime()-origin.getTime();for(const shift of source)if(shift.guardia_id)await validateShifts(shift.guardia_id,[{fecha:new Date(shift.fecha.getTime()+offset),hora_inicio:shift.hora_inicio,hora_fin:shift.hora_fin}]);await db.turno.createMany({data:source.map(({id,created_at,updated_at,...x})=>({...x,fecha:new Date(x.fecha.getTime()+offset),created_by_id:req.user!.id}))});res.status(201).json({message:`Se copiaron ${source.length} turnos`,count:source.length});}));
app.post('/api/turnos/programar-masivo',auth,permit('turnos'),asyncHandler(async(req,res)=>{const{guardia_ids,fecha,hora_inicio,hora_fin,tipo_turno='Dia',recinto_id}=req.body;if(!Array.isArray(guardia_ids)||!guardia_ids.length)return res.status(400).json({message:'Selecciona al menos un guardia'});const guards=await db.guardia.findMany({where:{id:{in:guardia_ids},estado:'Activo',empresa_id:req.user!.empresa_id!}}),site=recinto_id?await db.recinto.findFirst({where:{id:recinto_id,empresa_id:req.user!.empresa_id!}}):null,day=new Date(`${fecha}T00:00:00.000Z`);for(const guard of guards)await validateShifts(guard.id,[{fecha:day,hora_inicio,hora_fin}]);await db.turno.createMany({data:guards.map(guard=>({empresa_id:req.user!.empresa_id!,guardia_id:guard.id,guardia_nombre:guard.nombre,recinto_id:site?.id,recinto_nombre:site?.nombre,tipo_turno,fecha:day,hora_inicio,hora_fin,estado:'Programado',created_by_id:req.user!.id}))});res.status(201).json({message:`Se programaron ${guards.length} guardias`,count:guards.length});}));
app.get('/api/turnos/cobertura',auth,permit('turnos'),asyncHandler(async(req,res)=>{const start=new Date(`${String(req.query.desde||new Date().toISOString().slice(0,10))}T00:00:00.000Z`),end=new Date(`${String(req.query.hasta||req.query.desde||new Date().toISOString().slice(0,10))}T23:59:59.999Z`);const shifts=await db.turno.groupBy({by:['fecha','recinto_id','recinto_nombre','tipo_turno'],where:{fecha:{gte:start,lte:end},estado:{not:'Cancelado'}},_count:{_all:true}});res.json(shifts.map(x=>({...x,guardias:x._count._all,cobertura_minima:Number(req.query.minimo||1),cumple:x._count._all>=Number(req.query.minimo||1)})));}));
app.get('/api/turnos/exportar',auth,permit('turnos'),asyncHandler(async(req,res)=>{const shifts=await db.turno.findMany({orderBy:[{fecha:'asc'},{hora_inicio:'asc'}]});const rows=[['Fecha','Guardia','Recinto','Jornada','Inicio','Fin','Estado'],...shifts.map(x=>[x.fecha.toISOString().slice(0,10),x.guardia_nombre,x.recinto_nombre||x.ubicacion||'',x.tipo_turno,x.hora_inicio,x.hora_fin,x.estado])];if(req.query.formato==='pdf'){const esc=(v:unknown)=>String(v).replace(/[&<>]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]!));res.type('html').send(`<!doctype html><meta charset="utf-8"><title>Turnos</title><style>body{font:12px Arial}table{width:100%;border-collapse:collapse}th,td{border:1px solid #ccc;padding:6px}th{background:#0f766e;color:white}</style><h1>PlanificaciÃ³n de turnos</h1><table>${rows.map((r,i)=>`<tr>${r.map(v=>`<${i?'td':'th'}>${esc(v)}</${i?'td':'th'}>`).join('')}</tr>`).join('')}</table><script>print()</script>`);return}res.setHeader('Content-Disposition','attachment; filename="turnos.csv"');res.type('text/csv').send('\ufeff'+rows.map(r=>r.map(v=>`"${String(v).replaceAll('"','""')}"`).join(';')).join('\n'));}));
app.use('/api/database',databaseAdmin);
app.use('/api/rrhh',auth,permit('rrhh'),rrhh);
app.put('/api/profile',auth,asyncHandler(async(req,res)=>{const {password,current_password,...input}=req.body;const allowed=['full_name','telefono','cargo','foto_url'];const data:any=Object.fromEntries(Object.entries(input).filter(([key])=>allowed.includes(key)));const me=await db.user.findUniqueOrThrow({where:{id:req.user!.id}});if(password){if(password.length<8)return res.status(400).json({message:'La nueva contraseÃ±a debe tener al menos 8 caracteres'});if(!me.password||!await bcrypt.compare(current_password,me.password))return res.status(400).json({message:'ContraseÃ±a actual incorrecta'});data.password=await bcrypt.hash(password,12);data.must_change_password=false;}else if(me.must_change_password)return res.status(400).json({message:'Debes definir una nueva contraseÃ±a para continuar'});const updated=await db.$transaction(async transaction=>{const user=await transaction.user.update({where:{id:me.id},data});if(me.guardia_id)await transaction.guardia.update({where:{id:me.guardia_id},data:{nombre:data.full_name??me.full_name,telefono:data.telefono??me.telefono,foto_url:'foto_url' in data?data.foto_url:me.foto_url}});return user});res.json(publicUser(updated));}));app.delete('/api/profile',auth,asyncHandler(async(req,res)=>{await db.user.delete({where:{id:req.user!.id}});res.status(204).end();}));
app.use('/api',auth,crud);
app.use('/api',(req,res)=>res.status(404).json({message:`Ruta API no encontrada: ${req.method} ${req.originalUrl}`}));
app.use((err:any,req:any,res:any,next:any)=>{console.error(err);audit('error_api',{userId:req.user?.id,entity:req.method,entityId:String(req.originalUrl||'').slice(0,30),detail:{message:err.message,url:req.originalUrl},ip:req.ip,userAgent:req.get?.('user-agent')});const prismaConflict=err.code==='P2002',notFound=err.code==='P2025';res.status(err.name==='ZodError'?400:prismaConflict?409:notFound?404:err.status||500).json({message:err.name==='ZodError'?err.issues?.[0]?.message:prismaConflict?'Ya existe un registro con uno de los datos Ãºnicos ingresados':notFound?'El registro solicitado no existe':err.status?err.message:'OcurriÃ³ un error interno al procesar la solicitud'});});
async function migrateCompatibility(){
  const existing=async(table:string)=>new Set((await db.$queryRawUnsafe<Array<{COLUMN_NAME:string}>>(
    `SELECT COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = '${table}'`
  )).map(column=>column.COLUMN_NAME));
  await db.$executeRawUnsafe(`CREATE TABLE IF NOT EXISTS empresas (
    id VARCHAR(30) PRIMARY KEY,nombre VARCHAR(191) NOT NULL,slug VARCHAR(191) NOT NULL UNIQUE,rut VARCHAR(191) NULL,email VARCHAR(191) NULL,
    telefono VARCHAR(191) NULL,direccion VARCHAR(191) NULL,logo_url MEDIUMTEXT NULL,estado ENUM('Activa','Suspendida','Eliminada') NOT NULL DEFAULT 'Activa',
    modulos JSON NOT NULL,limite_usuarios INT NULL,limite_guardias INT NULL,limite_recintos INT NULL,vence_at DATETIME NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
  ) ENGINE=InnoDB`);
  await db.$executeRawUnsafe(`INSERT IGNORE INTO empresas (id,nombre,slug,modulos) VALUES ('empresa-principal','Empresa principal','principal',JSON_OBJECT('guardias',true,'turnos',true,'relevos',true,'rondas',true,'recintos',true,'entradas',true,'reportes',true,'alertas',true,'rrhh',true,'usuarios',true,'configuracion',true))`);
  const empresaColumns=await existing('empresas');
  const empresaDefinitions:Record<string,string>={website_url:'VARCHAR(500) NULL',descripcion:'TEXT NULL',servicios:'TEXT NULL',quote_email:'VARCHAR(191) NULL',public_page_enabled:'BOOLEAN NOT NULL DEFAULT FALSE'};
  for(const [column,definition] of Object.entries(empresaDefinitions))if(!empresaColumns.has(column))await db.$executeRawUnsafe(`ALTER TABLE empresas ADD COLUMN ${column} ${definition}`);
  await db.$executeRawUnsafe("ALTER TABLE users MODIFY COLUMN role ENUM('superadmin','admin','jefe_turno','guardia','establecimiento') NOT NULL DEFAULT 'guardia'");
  const userColumns=await existing('users');
  if(!userColumns.has('enabled'))await db.$executeRawUnsafe('ALTER TABLE users ADD COLUMN enabled BOOLEAN NOT NULL DEFAULT TRUE AFTER email_verified');
  if(!userColumns.has('guardia_id'))await db.$executeRawUnsafe('ALTER TABLE users ADD COLUMN guardia_id VARCHAR(30) NULL UNIQUE AFTER permisos');
  if(!userColumns.has('foto_url'))await db.$executeRawUnsafe('ALTER TABLE users ADD COLUMN foto_url MEDIUMTEXT NULL AFTER guardia_id');
  if(!userColumns.has('must_change_password'))await db.$executeRawUnsafe('ALTER TABLE users ADD COLUMN must_change_password BOOLEAN NOT NULL DEFAULT FALSE AFTER foto_url');
  if(!userColumns.has('failed_login_attempts'))await db.$executeRawUnsafe('ALTER TABLE users ADD COLUMN failed_login_attempts INT NOT NULL DEFAULT 0 AFTER enabled');
  if(!userColumns.has('locked_until'))await db.$executeRawUnsafe('ALTER TABLE users ADD COLUMN locked_until DATETIME NULL AFTER failed_login_attempts');
  if(!userColumns.has('last_login_at'))await db.$executeRawUnsafe('ALTER TABLE users ADD COLUMN last_login_at DATETIME NULL AFTER locked_until');
  await db.$executeRawUnsafe(`CREATE TABLE IF NOT EXISTS sessions (id VARCHAR(30) PRIMARY KEY,user_id VARCHAR(30) NOT NULL,expires_at DATETIME NOT NULL,revoked_at DATETIME NULL,ip_address VARCHAR(191) NULL,user_agent TEXT NULL,created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,KEY idx_sessions_user_revoked (user_id,revoked_at),KEY idx_sessions_expires (expires_at),CONSTRAINT fk_sessions_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE) ENGINE=InnoDB`);
  await db.$executeRawUnsafe(`CREATE TABLE IF NOT EXISTS audit_logs (id VARCHAR(30) PRIMARY KEY,user_id VARCHAR(30) NULL,action VARCHAR(191) NOT NULL,entity VARCHAR(191) NULL,entity_id VARCHAR(30) NULL,detail JSON NULL,ip_address VARCHAR(191) NULL,user_agent TEXT NULL,created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,KEY idx_audit_user_created (user_id,created_at),KEY idx_audit_action_created (action,created_at),CONSTRAINT fk_audit_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL) ENGINE=InnoDB`);
  const configColumns=await existing('configuracion');
  const configDefinitions:Record<string,string>={
    nextcloud_enabled:'BOOLEAN NOT NULL DEFAULT FALSE',nextcloud_url:'VARCHAR(500) NULL',nextcloud_user:'VARCHAR(190) NULL',nextcloud_password:'VARCHAR(500) NULL',nextcloud_folder:"VARCHAR(255) NOT NULL DEFAULT 'Seguridad-RRHH'",
    login_max_attempts:'INT NOT NULL DEFAULT 5',login_lock_minutes:'INT NOT NULL DEFAULT 15',login_ban_email_enabled:'BOOLEAN NOT NULL DEFAULT FALSE',login_ban_telegram_enabled:'BOOLEAN NOT NULL DEFAULT FALSE',
    smtp_host:'VARCHAR(190) NULL',smtp_port:'SMALLINT UNSIGNED NOT NULL DEFAULT 587',smtp_secure:'BOOLEAN NOT NULL DEFAULT FALSE',
    smtp_user:'VARCHAR(190) NULL',smtp_password:'VARCHAR(255) NULL',mail_from:'VARCHAR(255) NULL',
    telegram_enabled:'BOOLEAN NOT NULL DEFAULT FALSE',telegram_bot_token:'VARCHAR(255) NULL',telegram_chat_id:'VARCHAR(100) NULL',
    alert_email_enabled:'BOOLEAN NOT NULL DEFAULT FALSE',alert_telegram_enabled:'BOOLEAN NOT NULL DEFAULT TRUE',
    report_email_enabled:'BOOLEAN NOT NULL DEFAULT FALSE',report_telegram_enabled:'BOOLEAN NOT NULL DEFAULT FALSE',notification_email:'VARCHAR(190) NULL',shift_email_enabled:'BOOLEAN NOT NULL DEFAULT FALSE',
    timezone:"VARCHAR(80) NOT NULL DEFAULT 'America/Santiago'",date_format:"VARCHAR(20) NOT NULL DEFAULT 'DD/MM/YYYY'",time_format:"VARCHAR(10) NOT NULL DEFAULT '24h'",
    turno_dia_inicio:"VARCHAR(8) NOT NULL DEFAULT '08:00'",turno_dia_fin:"VARCHAR(8) NOT NULL DEFAULT '20:00'",turno_manana_inicio:"VARCHAR(8) NOT NULL DEFAULT '08:00'",turno_manana_fin:"VARCHAR(8) NOT NULL DEFAULT '16:00'",turno_tarde_inicio:"VARCHAR(8) NOT NULL DEFAULT '16:00'",turno_tarde_fin:"VARCHAR(8) NOT NULL DEFAULT '00:00'",turno_noche_inicio:"VARCHAR(8) NOT NULL DEFAULT '20:00'",turno_noche_fin:"VARCHAR(8) NOT NULL DEFAULT '08:00'",
    turno_dia_color:"VARCHAR(20) NOT NULL DEFAULT '#f59e0b'",turno_noche_color:"VARCHAR(20) NOT NULL DEFAULT '#2563eb'",turno_personalizado_color:"VARCHAR(20) NOT NULL DEFAULT '#7c3aed'",
    theme:"VARCHAR(30) NOT NULL DEFAULT 'esmeralda'",brand_name:"VARCHAR(100) NOT NULL DEFAULT 'Seguridad'",brand_subtitle:"VARCHAR(150) NOT NULL DEFAULT 'Centro de operaciones'",
    hero_title:"VARCHAR(255) NOT NULL DEFAULT 'Seguridad conectada, decisiones claras.'",hero_description:'TEXT NULL',hero_footer:"VARCHAR(255) NOT NULL DEFAULT 'ProtecciÃ³n visible. GestiÃ³n inteligente.'",
    logo_url:'MEDIUMTEXT NULL',icon_url:'MEDIUMTEXT NULL',hero_image_url:'MEDIUMTEXT NULL',public_page_enabled:'BOOLEAN NOT NULL DEFAULT FALSE',public_banner_color:"VARCHAR(20) NOT NULL DEFAULT '#e2e8f0'",
    company_contact_enabled:'BOOLEAN NOT NULL DEFAULT FALSE',company_contact_name:'VARCHAR(150) NULL',company_email:'VARCHAR(190) NULL',company_phone:'VARCHAR(40) NULL',company_address:'VARCHAR(255) NULL',company_website_url:'VARCHAR(500) NULL',
    company_title:"VARCHAR(255) NOT NULL DEFAULT 'Seguridad que inspira confianza'",company_description:'TEXT NULL',company_services:'TEXT NULL',quote_email:'VARCHAR(190) NULL'
  };
  for(const [column,definition] of Object.entries(configDefinitions)){
    if(!configColumns.has(column))await db.$executeRawUnsafe(`ALTER TABLE configuracion ADD COLUMN ${column} ${definition}`);
  }
  await db.$executeRawUnsafe("ALTER TABLE turnos MODIFY COLUMN tipo_turno ENUM('Manana','Tarde','Dia','Noche','Personalizado') NOT NULL");
  await db.$executeRawUnsafe(`CREATE TABLE IF NOT EXISTS relevos (
    id VARCHAR(30) PRIMARY KEY, turno_id VARCHAR(30) NULL, guardia_saliente_id VARCHAR(30) NULL, guardia_saliente_nombre VARCHAR(150) NOT NULL,
    guardia_entrante_id VARCHAR(30) NULL, guardia_entrante_nombre VARCHAR(150) NOT NULL, recinto_id VARCHAR(30) NULL, recinto_nombre VARCHAR(150) NULL,
    fecha_hora DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, novedades TEXT NOT NULL, estado_entrega VARCHAR(30) NOT NULL DEFAULT 'Completa', created_by_id VARCHAR(30) NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    KEY idx_relevos_fecha (fecha_hora), KEY idx_relevos_saliente (guardia_saliente_id), KEY idx_relevos_entrante (guardia_entrante_id),
    CONSTRAINT fk_relevos_creator FOREIGN KEY (created_by_id) REFERENCES users(id) ON DELETE SET NULL
  ) ENGINE=InnoDB`);
  await db.$executeRawUnsafe(`CREATE TABLE IF NOT EXISTS trabajadores (
    id VARCHAR(30) PRIMARY KEY, nombre VARCHAR(191) NOT NULL, documento VARCHAR(191) NOT NULL UNIQUE, fecha_nacimiento DATETIME NULL,
    nacionalidad VARCHAR(191) NULL, direccion VARCHAR(191) NULL, comuna VARCHAR(191) NULL, telefono VARCHAR(191) NULL,
    email_personal VARCHAR(191) NULL, email_corporativo VARCHAR(191) NULL, contacto_emergencia_nombre VARCHAR(191) NULL,
    contacto_emergencia_parentesco VARCHAR(191) NULL, contacto_emergencia_telefono VARCHAR(191) NULL, cargo VARCHAR(191) NOT NULL,
    area VARCHAR(191) NULL, supervisor VARCHAR(191) NULL, recinto VARCHAR(191) NULL, fecha_ingreso DATETIME NULL, tipo_contrato VARCHAR(191) NULL,
    jornada VARCHAR(191) NULL, estado VARCHAR(191) NOT NULL DEFAULT 'Activo', fecha_termino DATETIME NULL, motivo_termino VARCHAR(191) NULL,
    observaciones TEXT NULL, foto_url MEDIUMTEXT NULL, guardia_id VARCHAR(30) NULL UNIQUE, user_id VARCHAR(30) NULL UNIQUE, created_by_id VARCHAR(30) NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    KEY idx_trabajadores_estado (estado), KEY idx_trabajadores_cargo (cargo)
  ) ENGINE=InnoDB`);
  await db.$executeRawUnsafe(`CREATE TABLE IF NOT EXISTS eventos_rrhh (
    id VARCHAR(30) PRIMARY KEY, trabajador_id VARCHAR(30) NOT NULL, tipo VARCHAR(191) NOT NULL, titulo VARCHAR(191) NOT NULL,
    fecha_inicio DATETIME NOT NULL, fecha_fin DATETIME NULL, estado VARCHAR(191) NOT NULL DEFAULT 'Registrado', dias DECIMAL(8,2) NULL,
    detalle TEXT NULL, entidad VARCHAR(191) NULL, folio VARCHAR(191) NULL, archivo_url MEDIUMTEXT NULL, confidencial BOOLEAN NOT NULL DEFAULT FALSE,
    created_by_id VARCHAR(30) NULL, created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    KEY idx_eventos_trabajador_tipo (trabajador_id,tipo), KEY idx_eventos_fecha (fecha_inicio),
    CONSTRAINT fk_eventos_trabajador FOREIGN KEY (trabajador_id) REFERENCES trabajadores(id) ON DELETE CASCADE
  ) ENGINE=InnoDB`);
  const eventColumns=await existing('eventos_rrhh');
  if(!eventColumns.has('archivo_cloud_path'))await db.$executeRawUnsafe('ALTER TABLE eventos_rrhh ADD COLUMN archivo_cloud_path VARCHAR(500) NULL AFTER archivo_url');
  if(!eventColumns.has('notificar_email'))await db.$executeRawUnsafe('ALTER TABLE eventos_rrhh ADD COLUMN notificar_email BOOLEAN NOT NULL DEFAULT FALSE AFTER confidencial');
  if(!eventColumns.has('notificar_telegram'))await db.$executeRawUnsafe('ALTER TABLE eventos_rrhh ADD COLUMN notificar_telegram BOOLEAN NOT NULL DEFAULT FALSE AFTER notificar_email');
  if(!eventColumns.has('inicio_notificado_at'))await db.$executeRawUnsafe('ALTER TABLE eventos_rrhh ADD COLUMN inicio_notificado_at DATETIME NULL AFTER notificar_telegram');
  if(!eventColumns.has('termino_notificado_at'))await db.$executeRawUnsafe('ALTER TABLE eventos_rrhh ADD COLUMN termino_notificado_at DATETIME NULL AFTER inicio_notificado_at');
  await db.$executeRawUnsafe(`CREATE TABLE IF NOT EXISTS amonestaciones (
    id VARCHAR(30) PRIMARY KEY, folio VARCHAR(191) NOT NULL UNIQUE, trabajador_id VARCHAR(30) NOT NULL, fecha_hecho DATETIME NOT NULL,
    lugar VARCHAR(191) NULL, tipo_incumplimiento VARCHAR(191) NOT NULL, hechos TEXT NOT NULL, norma_relacionada TEXT NULL, descargos TEXT NULL,
    medida TEXT NULL, responsable VARCHAR(191) NOT NULL, testigos VARCHAR(191) NULL, fecha_notificacion DATETIME NULL,
    estado VARCHAR(191) NOT NULL DEFAULT 'Borrador', constancia_recepcion VARCHAR(191) NULL, enviada_email_at DATETIME NULL, created_by_id VARCHAR(30) NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    KEY idx_amonestaciones_trabajador (trabajador_id), KEY idx_amonestaciones_fecha (fecha_hecho),
    CONSTRAINT fk_amonestaciones_trabajador FOREIGN KEY (trabajador_id) REFERENCES trabajadores(id) ON DELETE CASCADE
  ) ENGINE=InnoDB`);
  // Todas las tablas deben existir antes de aplicarles la separaciÃ³n por empresa.
  // En instalaciones nuevas, las tablas de RRHH se crean en este mismo arranque.
  const tenantTables=['users','guardias','recintos','turnos','rondas','entradas','reportes','alertas','relevos','trabajadores','eventos_rrhh','amonestaciones'];
  for(const table of tenantTables){const columns=await existing(table);if(!columns.has('empresa_id'))await db.$executeRawUnsafe(`ALTER TABLE ${table} ADD COLUMN empresa_id VARCHAR(30) NULL AFTER id`);await db.$executeRawUnsafe(`UPDATE ${table} SET empresa_id='empresa-principal' WHERE empresa_id IS NULL`);if(table!=='users')await db.$executeRawUnsafe(`ALTER TABLE ${table} MODIFY empresa_id VARCHAR(30) NOT NULL`);}
  for(const [table,column,indexName] of [['guardias','documento','uq_guardias_empresa_documento'],['trabajadores','documento','uq_trabajadores_empresa_documento'],['amonestaciones','folio','uq_amonestaciones_empresa_folio']] as const){
    const indexes=await db.$queryRawUnsafe<Array<{INDEX_NAME:string;columns_count:bigint}>>(`SELECT INDEX_NAME,COUNT(*) columns_count FROM information_schema.STATISTICS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='${table}' AND NON_UNIQUE=0 AND INDEX_NAME<>'PRIMARY' GROUP BY INDEX_NAME`);
    for(const index of indexes)if(Number(index.columns_count)===1&&index.INDEX_NAME!==indexName){const columns=await db.$queryRawUnsafe<Array<{COLUMN_NAME:string}>>(`SELECT COLUMN_NAME FROM information_schema.STATISTICS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='${table}' AND INDEX_NAME='${index.INDEX_NAME}'`);if(columns[0]?.COLUMN_NAME===column)await db.$executeRawUnsafe(`ALTER TABLE ${table} DROP INDEX \`${index.INDEX_NAME}\``);}
    if(!indexes.some(index=>index.INDEX_NAME===indexName))await db.$executeRawUnsafe(`ALTER TABLE ${table} ADD UNIQUE INDEX ${indexName} (empresa_id,${column})`);
  }
  const guardiaPhoto=await db.$queryRawUnsafe<Array<{DATA_TYPE:string}>>(
    "SELECT DATA_TYPE FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'guardias' AND COLUMN_NAME = 'foto_url'"
  );
  if(guardiaPhoto[0]&&guardiaPhoto[0].DATA_TYPE.toLowerCase()!=='mediumtext'){
    await db.$executeRawUnsafe('ALTER TABLE guardias MODIFY COLUMN foto_url MEDIUMTEXT NULL');
  }
  const columns=await db.$queryRawUnsafe<Array<{COLUMN_NAME:string;DATA_TYPE:string}>>(
    "SELECT COLUMN_NAME, DATA_TYPE FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'turnos' AND COLUMN_NAME IN ('hora_inicio','hora_fin')"
  );
  if(columns.some(column=>column.DATA_TYPE.toLowerCase()==='time')){
    console.log('Migrando horarios de turnos de TIME a VARCHAR(8)...');
    await db.$executeRawUnsafe('ALTER TABLE turnos MODIFY COLUMN hora_inicio VARCHAR(8) NOT NULL, MODIFY COLUMN hora_fin VARCHAR(8) NOT NULL');
  }
}

async function start(){
  let lastError:unknown;
  for(let attempt=1;attempt<=15;attempt++){
    try{await migrateCompatibility();lastError=undefined;break}
    catch(error){lastError=error;console.warn(`Base de datos no disponible (intento ${attempt}/15). Reintentando en 3 segundos...`);await new Promise(resolve=>setTimeout(resolve,3000))}
  }
  if(lastError)throw lastError;
  const adminEmail=process.env.INITIAL_ADMIN_EMAIL||'admin@seguridad.cl';
  if(!await db.user.findUnique({where:{email:adminEmail}})){
    const initialPassword=process.env.INITIAL_ADMIN_PASSWORD;
    if(!initialPassword||initialPassword.length<12)throw new Error('INITIAL_ADMIN_PASSWORD debe existir y tener al menos 12 caracteres');
    await db.user.create({data:{full_name:'Propietario de la plataforma',email:adminEmail,password:await bcrypt.hash(initialPassword,12),role:'superadmin',email_verified:true,must_change_password:true,permisos:{empresas:true}}});
    console.log(`Administrador inicial creado: ${adminEmail}. Debe cambiar su contraseÃ±a al ingresar.`);
  }
  await db.user.updateMany({where:{email:adminEmail,role:'admin'},data:{role:'superadmin',empresa_id:null,permisos:{empresas:true}}});
  await processRrhhNotifications();
  setInterval(()=>processRrhhNotifications(),60*60_000).unref();
  server.listen(Number(process.env.PORT||4000),()=>console.log(`Seguridad-RRHH API en http://localhost:${process.env.PORT||4000}`));
}
start().catch(error=>{console.error('No fue posible iniciar Seguridad-RRHH:',error);process.exit(1)});
