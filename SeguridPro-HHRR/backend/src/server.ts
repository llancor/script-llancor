import 'dotenv/config';
import express from 'express'; import cors from 'cors'; import helmet from 'helmet'; import morgan from 'morgan';
import { createServer } from 'http'; import { Server } from 'socket.io'; import rateLimit from 'express-rate-limit'; import bcrypt from 'bcryptjs';
import authRoutes from './auth.js'; import { crud } from './crud.js'; import { auth,admin,permit,asyncHandler } from './middleware.js'; import { audit,db,encryptSecret,publicUser,sendEmail,sendTelegram } from './lib.js';
import { testNextcloud } from './nextcloud.js';
import { databaseAdmin } from './database-admin.js';
import { processRrhhNotifications,rrhh } from './rrhh.js';
import { validateShifts } from './shift-rules.js';
const app=express();const server=createServer(app);const io=new Server(server,{cors:{origin:process.env.FRONTEND_URL}});app.set('io',io);
app.use(helmet());app.use(cors({origin:process.env.FRONTEND_URL}));app.use(express.json({limit:'50mb'}));app.use(morgan('dev'));app.use('/api/auth',rateLimit({windowMs:60_000,limit:30}),authRoutes);
app.get('/api/health',(req,res)=>res.json({status:'ok'}));
app.get('/api/public/branding',asyncHandler(async(req,res)=>{const c=await db.configuracion.upsert({where:{id:1},update:{},create:{id:1}});res.json({timezone:c.timezone,date_format:c.date_format,time_format:c.time_format,theme:c.theme,brand_name:c.brand_name,brand_subtitle:c.brand_subtitle,hero_title:c.hero_title,hero_description:c.hero_description,hero_footer:c.hero_footer,logo_url:c.logo_url,icon_url:c.icon_url,hero_image_url:c.hero_image_url,public_page_enabled:c.public_page_enabled,public_banner_color:c.public_banner_color,company_title:c.company_title,company_description:c.company_description,company_services:c.company_services,...(c.company_contact_enabled?{company_contact_enabled:true,company_contact_name:c.company_contact_name,company_email:c.company_email,company_phone:c.company_phone,company_address:c.company_address,company_website_url:c.company_website_url}:{company_contact_enabled:false})});}));
app.post('/api/public/quote',rateLimit({windowMs:60_000,limit:5}),asyncHandler(async(req,res)=>{const {nombre,email,telefono,empresa,mensaje}=req.body;if(!nombre||!email||!mensaje)return res.status(400).json({message:'Nombre, email y mensaje son obligatorios'});const c=await db.configuracion.findUnique({where:{id:1}});if(!c?.public_page_enabled)return res.status(404).json({message:'Página no disponible'});const destination=c.quote_email||c.smtp_user||process.env.SMTP_USER;if(!destination)return res.status(503).json({message:'No hay un correo de cotizaciones configurado'});await sendEmail(destination,`Solicitud de cotización: ${empresa||nombre}`,`Nombre: ${nombre}\nEmail: ${email}\nTeléfono: ${telefono||'No indicado'}\nEmpresa: ${empresa||'No indicada'}\n\n${mensaje}`);res.json({message:'Solicitud enviada. Nos pondremos en contacto contigo.'});}));
app.get('/api/dashboard',auth,asyncHandler(async(req,res)=>{
  const start=new Date();start.setHours(0,0,0,0);const end=new Date(start);end.setDate(end.getDate()+1);
  const all=req.user?.role==='admin'||req.user?.permisos?.ver_registros==='todos';const scope=(model:string):any=>{if(all)return{};const creator={created_by_id:req.user!.id};const guardiaId=req.user?.guardia_id;if(!guardiaId)return creator;if(model==='guardia')return{OR:[creator,{id:guardiaId}]};return{OR:[creator,{guardia_id:guardiaId}]}};
  const [guardias,turnos,alertas,entradas,reportes,rondas,alertasLista,turnosLista]=await Promise.all([
    db.guardia.count({where:{AND:[scope('guardia'),{estado:'Activo'}]}}),db.turno.count({where:{AND:[scope('turno'),{fecha:{gte:start,lt:end}}]}}),db.alerta.count({where:{AND:[scope('alerta'),{estado:'Activa'}]}}),db.entrada.count({where:{AND:[scope('entrada'),{estado:'Dentro'}]}}),db.reporte.count({where:{AND:[scope('reporte'),{estado:'Abierto'}]}}),db.ronda.findMany({where:scope('ronda'),take:5,orderBy:{fecha_hora_inicio:'desc'}}),db.alerta.findMany({where:{AND:[scope('alerta'),{estado:'Activa'}]},take:5,orderBy:{fecha:'desc'}}),db.turno.findMany({where:{AND:[scope('turno'),{fecha:{gte:start,lt:end}}]},take:5,orderBy:{hora_inicio:'asc'}})
  ]);
  res.json({stats:{guardias,turnos,alertas,entradas,reportes,rondas:rondas.length},rondas,alertasLista,turnosLista});
}));
app.get('/api/lookups/recintos',auth,asyncHandler(async(req,res)=>res.json(await db.recinto.findMany({where:{estado:'Activo'},select:{id:true,nombre:true,direccion:true},orderBy:{nombre:'asc'}}))));
app.get('/api/lookups/guardias',auth,asyncHandler(async(req,res)=>{const limited=req.user?.role!=='admin'&&req.user?.permisos?.ver_registros!=='todos'&&req.user?.guardia_id;res.json(await db.guardia.findMany({where:{estado:'Activo',...(limited?{id:req.user!.guardia_id}:{})},select:{id:true,nombre:true,documento:true,recinto_id:true,recinto_nombre:true},orderBy:{nombre:'asc'}}))}));
app.get('/api/users',auth,admin,asyncHandler(async(req,res)=>res.json((await db.user.findMany({orderBy:{created_at:'desc'}})).map(publicUser))));
app.get('/api/audit',auth,admin,asyncHandler(async(req,res)=>{const limit=Math.min(500,Math.max(1,Number(req.query.limit||100)));res.json(await db.auditLog.findMany({take:limit,orderBy:{created_at:'desc'},include:{user:{select:{full_name:true,email:true}}}}))}));
app.post('/api/users/invite',auth,admin,asyncHandler(async(req,res)=>{const {password,send_invitation,...data}=req.body;if(!password||password.length<8)return res.status(400).json({message:'La contraseña debe tener al menos 8 caracteres'});const user=await db.user.create({data:{...data,password:await bcrypt.hash(password,12),email_verified:true,enabled:data.enabled??true,must_change_password:true}});if(send_invitation)await sendEmail(user.email,'Cuenta creada en Seguridad-RRHH',`Tu cuenta fue creada. Ingresa con ${user.email} y la contraseña proporcionada por el administrador. Deberás cambiarla al ingresar.`);res.status(201).json(publicUser(user));}));
app.put('/api/users/:id',auth,admin,asyncHandler(async(req,res)=>{const allowed=['full_name','email','role','rango','telefono','cargo','permisos','enabled'];const data=Object.fromEntries(Object.entries(req.body).filter(([key])=>allowed.includes(key)));res.json(publicUser(await db.user.update({where:{id:req.params.id},data})));}));
app.put('/api/users/:id/password',auth,admin,asyncHandler(async(req,res)=>{const {password}=req.body;if(!password||password.length<8)return res.status(400).json({message:'La contraseña debe tener al menos 8 caracteres'});await db.user.update({where:{id:req.params.id},data:{password:await bcrypt.hash(password,12),email_verified:true,must_change_password:true}});res.json({message:'Contraseña restablecida. El usuario deberá cambiarla al ingresar'});}));
app.post('/api/guardias/:id/activar-acceso',auth,admin,asyncHandler(async(req,res)=>{const guard=await db.guardia.findUniqueOrThrow({where:{id:req.params.id},include:{usuario:true}});if(guard.usuario){if(!guard.usuario.enabled){await db.user.update({where:{id:guard.usuario.id},data:{enabled:true}});return res.json({message:'Acceso web reactivado correctamente'})}return res.status(409).json({message:'Este guardia ya tiene un perfil web activo'});}const email=String(req.body.email||guard.email||'').trim().toLowerCase(),password=String(req.body.password||'');if(!/^\S+@\S+\.\S+$/.test(email))return res.status(400).json({message:'El guardia necesita un correo válido'});if(password.length<10)return res.status(400).json({message:'La contraseña temporal debe tener al menos 10 caracteres'});if(await db.user.findUnique({where:{email}}))return res.status(409).json({message:'Ya existe otro usuario con ese correo'});const permisos={guardias:false,turnos:false,relevos:true,rondas:true,recintos:false,entradas:true,reportes:true,alertas:true,rrhh:false,usuarios:false,configuracion:false,editar_entradas:true,editar_reportes:true,editar_alertas:true,eliminar_entradas:false,eliminar_reportes:false,eliminar_alertas:false,ver_registros:'propios'};const user=await db.user.create({data:{full_name:guard.nombre,email,password:await bcrypt.hash(password,12),role:'guardia',rango:guard.rango,telefono:guard.telefono,permisos,guardia_id:guard.id,foto_url:guard.foto_url,email_verified:true,enabled:true,must_change_password:true}});if(req.body.send_invitation)sendEmail(email,'Acceso activado en Seguridad',`Hola ${guard.nombre}. Tu acceso fue activado. Usuario: ${email}\nContraseña temporal: ${password}\nDeberás cambiarla al ingresar.`).catch(console.error);await audit('activar_acceso_guardia',{userId:req.user!.id,entity:'guardia',entityId:guard.id,detail:{usuario:user.id},ip:req.ip,userAgent:req.get('user-agent')});res.status(201).json({message:'Perfil web creado y activado correctamente',user:publicUser(user)});}));
app.delete('/api/users/:id',auth,admin,asyncHandler(async(req,res)=>{if(req.params.id===req.user!.id)return res.status(400).json({message:'No puedes eliminar tu usuario desde administración'});await db.user.delete({where:{id:req.params.id}});res.status(204).end();}));
const safeConfig=(c:any)=>({...c,smtp_password:undefined,telegram_bot_token:undefined,nextcloud_password:undefined,smtp_password_configured:!!c.smtp_password,telegram_token_configured:!!c.telegram_bot_token,nextcloud_password_configured:!!c.nextcloud_password});
app.get('/api/config',auth,permit('configuracion'),asyncHandler(async(req,res)=>res.json(safeConfig(await db.configuracion.upsert({where:{id:1},update:{},create:{id:1}})))));app.put('/api/config',auth,admin,asyncHandler(async(req,res)=>{const allowed=['permitir_registro_publico','login_max_attempts','login_lock_minutes','login_ban_email_enabled','login_ban_telegram_enabled','nextcloud_enabled','nextcloud_url','nextcloud_user','nextcloud_password','nextcloud_folder','smtp_host','smtp_port','smtp_secure','smtp_user','smtp_password','mail_from','telegram_enabled','telegram_bot_token','telegram_chat_id','alert_email_enabled','alert_telegram_enabled','report_email_enabled','report_telegram_enabled','notification_email','shift_email_enabled','timezone','date_format','time_format','turno_dia_inicio','turno_dia_fin','turno_manana_inicio','turno_manana_fin','turno_tarde_inicio','turno_tarde_fin','turno_noche_inicio','turno_noche_fin','turno_dia_color','turno_noche_color','turno_personalizado_color','theme','brand_name','brand_subtitle','hero_title','hero_description','hero_footer','logo_url','icon_url','hero_image_url','public_page_enabled','public_banner_color','company_contact_enabled','company_contact_name','company_email','company_phone','company_address','company_website_url','company_title','company_description','company_services','quote_email'];const data:any=Object.fromEntries(Object.entries(req.body).filter(([key])=>allowed.includes(key)));if('login_max_attempts'in data)data.login_max_attempts=Math.min(20,Math.max(1,Number(data.login_max_attempts)||5));if('login_lock_minutes'in data)data.login_lock_minutes=Math.min(1440,Math.max(1,Number(data.login_lock_minutes)||15));if(!data.smtp_password)delete data.smtp_password;if(!data.telegram_bot_token)delete data.telegram_bot_token;if(data.nextcloud_password)data.nextcloud_password=encryptSecret(String(data.nextcloud_password));else delete data.nextcloud_password;const config=await db.configuracion.upsert({where:{id:1},update:data,create:{id:1,...data}});res.json(safeConfig(config));}));
app.post('/api/config/test-email',auth,admin,asyncHandler(async(req,res)=>{if(!req.body.email)return res.status(400).json({message:'Indica un email de destino'});await sendEmail(req.body.email,'Prueba SMTP Seguridad-RRHH','La configuración SMTP funciona correctamente.');res.json({message:'Correo de prueba enviado'});}));
app.post('/api/config/test-telegram',auth,admin,asyncHandler(async(req,res)=>{await sendTelegram('La configuración de Telegram funciona correctamente.');res.json({message:'Mensaje de prueba enviado'});}));
app.post('/api/config/test-nextcloud',auth,admin,asyncHandler(async(req,res)=>{await testNextcloud();res.json({message:'Conexión con Nextcloud correcta'});}));
app.post('/api/turnos/programar',auth,permit('turnos'),asyncHandler(async(req,res)=>{
  const {guardia_id,guardia_nombre,recinto_id,recinto_nombre,tipo_turno,fecha,hora_inicio,hora_fin,horas_colacion=0,ubicacion,observaciones,periodo='dia',dias_semana=[]}=req.body;
  if(!guardia_id||!guardia_nombre||!fecha||!hora_inicio||!hora_fin)return res.status(400).json({message:'Guardia, fecha y horario son obligatorios'});
  if(!['Manana','Tarde','Dia','Noche','Personalizado'].includes(tipo_turno))return res.status(400).json({message:'Tipo de turno inválido'});
  if(hora_inicio===hora_fin)return res.status(400).json({message:'La hora de inicio y término deben ser diferentes'});
  const lunch=Number(horas_colacion);if(!Number.isFinite(lunch)||lunch<0||lunch>=24)return res.status(400).json({message:'Las horas de colación deben estar entre 0 y menos de 24'});
  if(!['dia','semana'].includes(periodo))return res.status(400).json({message:'El período de programación no es válido'});
  const start=new Date(`${fecha}T00:00:00.000Z`);if(Number.isNaN(start.getTime()))return res.status(400).json({message:'Fecha inválida'});
  const dates:Date[]=[];
  if(periodo==='semana'){
    if(!Array.isArray(dias_semana)||!dias_semana.length)return res.status(400).json({message:'Selecciona al menos un día de trabajo'});
    const selected=[...new Set(dias_semana.map(Number))].filter(day=>Number.isInteger(day)&&day>=1&&day<=7);
    if(!selected.length)return res.status(400).json({message:'Los días seleccionados no son válidos'});
    const monday=new Date(start);monday.setUTCDate(start.getUTCDate()-((start.getUTCDay()+6)%7));
    for(const day of selected.sort((a,b)=>a-b)){const date=new Date(monday);date.setUTCDate(monday.getUTCDate()+day-1);dates.push(date)}
  }else dates.push(start);
  await validateShifts(guardia_id,dates.map(day=>({fecha:day,hora_inicio,hora_fin,horas_colacion:lunch})));
  await db.turno.createMany({data:dates.map(day=>({guardia_id,guardia_nombre,recinto_id:recinto_id||null,recinto_nombre:recinto_nombre||null,tipo_turno,fecha:day,hora_inicio,hora_fin,horas_colacion:lunch,ubicacion:ubicacion||null,observaciones:observaciones||null,estado:'Programado',created_by_id:req.user!.id}))});
  const [guardia,config]=await Promise.all([db.guardia.findUnique({where:{id:guardia_id},select:{email:true}}),db.configuracion.findUnique({where:{id:1}})]);
  if(config?.shift_email_enabled&&guardia?.email)sendEmail(guardia.email,`Programación de turnos Seguridad-RRHH`,`${guardia_nombre}: ${dates.length} turno(s) desde ${fecha}, horario ${hora_inicio} a ${hora_fin}, ${recinto_nombre||ubicacion||'sin recinto indicado'}.`).catch(error=>console.error('No se pudo enviar programación:',error));
  res.status(201).json({message:`Se crearon ${dates.length} turno(s)`,count:dates.length});
}));
app.post('/api/turnos/copiar-semana',auth,permit('turnos'),asyncHandler(async(req,res)=>{const{fecha_origen,fecha_destino}=req.body;if(!fecha_origen||!fecha_destino)return res.status(400).json({message:'Indica semana de origen y destino'});const origin=new Date(`${fecha_origen}T00:00:00.000Z`),target=new Date(`${fecha_destino}T00:00:00.000Z`),end=new Date(origin);end.setUTCDate(end.getUTCDate()+7);const source=await db.turno.findMany({where:{fecha:{gte:origin,lt:end},estado:{not:'Cancelado'}}});if(!source.length)return res.status(404).json({message:'La semana de origen no tiene turnos'});const offset=target.getTime()-origin.getTime();for(const shift of source)if(shift.guardia_id)await validateShifts(shift.guardia_id,[{fecha:new Date(shift.fecha.getTime()+offset),hora_inicio:shift.hora_inicio,hora_fin:shift.hora_fin}]);await db.turno.createMany({data:source.map(({id,created_at,updated_at,...x})=>({...x,fecha:new Date(x.fecha.getTime()+offset),created_by_id:req.user!.id}))});res.status(201).json({message:`Se copiaron ${source.length} turnos`,count:source.length});}));
app.post('/api/turnos/programar-masivo',auth,permit('turnos'),asyncHandler(async(req,res)=>{const{guardia_ids,fecha,hora_inicio,hora_fin,tipo_turno='Dia',recinto_id}=req.body;if(!Array.isArray(guardia_ids)||!guardia_ids.length)return res.status(400).json({message:'Selecciona al menos un guardia'});const guards=await db.guardia.findMany({where:{id:{in:guardia_ids},estado:'Activo'}}),site=recinto_id?await db.recinto.findUnique({where:{id:recinto_id}}):null,day=new Date(`${fecha}T00:00:00.000Z`);for(const guard of guards)await validateShifts(guard.id,[{fecha:day,hora_inicio,hora_fin}]);await db.turno.createMany({data:guards.map(guard=>({guardia_id:guard.id,guardia_nombre:guard.nombre,recinto_id:site?.id,recinto_nombre:site?.nombre,tipo_turno,fecha:day,hora_inicio,hora_fin,estado:'Programado',created_by_id:req.user!.id}))});res.status(201).json({message:`Se programaron ${guards.length} guardias`,count:guards.length});}));
app.get('/api/turnos/cobertura',auth,permit('turnos'),asyncHandler(async(req,res)=>{const start=new Date(`${String(req.query.desde||new Date().toISOString().slice(0,10))}T00:00:00.000Z`),end=new Date(`${String(req.query.hasta||req.query.desde||new Date().toISOString().slice(0,10))}T23:59:59.999Z`);const shifts=await db.turno.groupBy({by:['fecha','recinto_id','recinto_nombre','tipo_turno'],where:{fecha:{gte:start,lte:end},estado:{not:'Cancelado'}},_count:{_all:true}});res.json(shifts.map(x=>({...x,guardias:x._count._all,cobertura_minima:Number(req.query.minimo||1),cumple:x._count._all>=Number(req.query.minimo||1)})));}));
app.get('/api/turnos/exportar',auth,permit('turnos'),asyncHandler(async(req,res)=>{const shifts=await db.turno.findMany({orderBy:[{fecha:'asc'},{hora_inicio:'asc'}]});const rows=[['Fecha','Guardia','Recinto','Jornada','Inicio','Fin','Estado'],...shifts.map(x=>[x.fecha.toISOString().slice(0,10),x.guardia_nombre,x.recinto_nombre||x.ubicacion||'',x.tipo_turno,x.hora_inicio,x.hora_fin,x.estado])];if(req.query.formato==='pdf'){const esc=(v:unknown)=>String(v).replace(/[&<>]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]!));res.type('html').send(`<!doctype html><meta charset="utf-8"><title>Turnos</title><style>body{font:12px Arial}table{width:100%;border-collapse:collapse}th,td{border:1px solid #ccc;padding:6px}th{background:#0f766e;color:white}</style><h1>Planificación de turnos</h1><table>${rows.map((r,i)=>`<tr>${r.map(v=>`<${i?'td':'th'}>${esc(v)}</${i?'td':'th'}>`).join('')}</tr>`).join('')}</table><script>print()</script>`);return}res.setHeader('Content-Disposition','attachment; filename="turnos.csv"');res.type('text/csv').send('\ufeff'+rows.map(r=>r.map(v=>`"${String(v).replaceAll('"','""')}"`).join(';')).join('\n'));}));
app.use('/api/database',databaseAdmin);
app.use('/api/rrhh',auth,rrhh);
app.put('/api/profile',auth,asyncHandler(async(req,res)=>{const {password,current_password,...input}=req.body;const allowed=['full_name','telefono','cargo','foto_url'];const data:any=Object.fromEntries(Object.entries(input).filter(([key])=>allowed.includes(key)));const me=await db.user.findUniqueOrThrow({where:{id:req.user!.id}});if(password){if(password.length<8)return res.status(400).json({message:'La nueva contraseña debe tener al menos 8 caracteres'});if(!me.password||!await bcrypt.compare(current_password,me.password))return res.status(400).json({message:'Contraseña actual incorrecta'});data.password=await bcrypt.hash(password,12);data.must_change_password=false;}else if(me.must_change_password)return res.status(400).json({message:'Debes definir una nueva contraseña para continuar'});const updated=await db.$transaction(async transaction=>{const user=await transaction.user.update({where:{id:me.id},data});if(me.guardia_id)await transaction.guardia.update({where:{id:me.guardia_id},data:{nombre:data.full_name??me.full_name,telefono:data.telefono??me.telefono,foto_url:'foto_url' in data?data.foto_url:me.foto_url}});return user});res.json(publicUser(updated));}));app.delete('/api/profile',auth,asyncHandler(async(req,res)=>{await db.user.delete({where:{id:req.user!.id}});res.status(204).end();}));
app.use('/api',auth,crud);
app.use('/api',(req,res)=>res.status(404).json({message:`Ruta API no encontrada: ${req.method} ${req.originalUrl}`}));
app.use((err:any,req:any,res:any,next:any)=>{console.error(err);audit('error_api',{userId:req.user?.id,entity:req.method,entityId:req.originalUrl,detail:{message:err.message},ip:req.ip,userAgent:req.get?.('user-agent')});res.status(err.name==='ZodError'?400:err.status||500).json({message:err.issues?.[0]?.message||err.message||'Error interno'});});
async function migrateCompatibility(){
  const existing=async(table:string)=>new Set((await db.$queryRawUnsafe<Array<{COLUMN_NAME:string}>>(
    `SELECT COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = '${table}'`
  )).map(column=>column.COLUMN_NAME));
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
    hero_title:"VARCHAR(255) NOT NULL DEFAULT 'Seguridad conectada, decisiones claras.'",hero_description:'TEXT NULL',hero_footer:"VARCHAR(255) NOT NULL DEFAULT 'Protección visible. Gestión inteligente.'",
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
  const turnoLunchColumns=await db.$queryRawUnsafe<Array<{COLUMN_NAME:string}>>("SELECT COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'turnos'");
  if(!turnoLunchColumns.some(column=>column.COLUMN_NAME==='horas_colacion'))await db.$executeRawUnsafe('ALTER TABLE turnos ADD COLUMN horas_colacion DECIMAL(4,2) NOT NULL DEFAULT 0 AFTER hora_fin');
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
    await db.user.create({data:{full_name:'Administrador Seguridad',email:adminEmail,password:await bcrypt.hash(initialPassword,12),role:'admin',email_verified:true,must_change_password:true,permisos:{guardias:true,turnos:true,relevos:true,rondas:true,recintos:true,entradas:true,reportes:true,alertas:true,usuarios:true,configuracion:true,rrhh:true}}});
    console.log(`Administrador inicial creado: ${adminEmail}. Debe cambiar su contraseña al ingresar.`);
  }
  await processRrhhNotifications();
  setInterval(()=>processRrhhNotifications(),60*60_000).unref();
  server.listen(Number(process.env.PORT||4000),()=>console.log(`Seguridad-RRHH API en http://localhost:${process.env.PORT||4000}`));
}
start().catch(error=>{console.error('No fue posible iniciar Seguridad-RRHH:',error);process.exit(1)});
