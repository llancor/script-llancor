import 'dotenv/config';
import express from 'express'; import cors from 'cors'; import helmet from 'helmet'; import morgan from 'morgan';
import { createServer } from 'http'; import { Server } from 'socket.io'; import rateLimit from 'express-rate-limit'; import bcrypt from 'bcryptjs';
import authRoutes from './auth.js'; import { crud } from './crud.js'; import { auth,admin,permit,asyncHandler } from './middleware.js'; import { db,publicUser,sendEmail,sendTelegram } from './lib.js';
import { databaseAdmin } from './database-admin.js';
const app=express();const server=createServer(app);const io=new Server(server,{cors:{origin:process.env.FRONTEND_URL}});app.set('io',io);
app.use(helmet());app.use(cors({origin:process.env.FRONTEND_URL}));app.use(express.json({limit:'50mb'}));app.use(morgan('dev'));app.use('/api/auth',rateLimit({windowMs:60_000,limit:30}),authRoutes);
app.get('/api/health',(req,res)=>res.json({status:'ok'}));
app.get('/api/public/branding',asyncHandler(async(req,res)=>{const c=await db.configuracion.upsert({where:{id:1},update:{},create:{id:1}});res.json({theme:c.theme,brand_name:c.brand_name,brand_subtitle:c.brand_subtitle,hero_title:c.hero_title,hero_description:c.hero_description,hero_footer:c.hero_footer,logo_url:c.logo_url,icon_url:c.icon_url,hero_image_url:c.hero_image_url,public_page_enabled:c.public_page_enabled,public_banner_color:c.public_banner_color,company_title:c.company_title,company_description:c.company_description,company_services:c.company_services,...(c.company_contact_enabled?{company_contact_enabled:true,company_contact_name:c.company_contact_name,company_email:c.company_email,company_phone:c.company_phone,company_address:c.company_address,company_website_url:c.company_website_url}:{company_contact_enabled:false})});}));
app.post('/api/public/quote',rateLimit({windowMs:60_000,limit:5}),asyncHandler(async(req,res)=>{const {nombre,email,telefono,empresa,mensaje}=req.body;if(!nombre||!email||!mensaje)return res.status(400).json({message:'Nombre, email y mensaje son obligatorios'});const c=await db.configuracion.findUnique({where:{id:1}});if(!c?.public_page_enabled)return res.status(404).json({message:'Página no disponible'});const destination=c.quote_email||c.smtp_user||process.env.SMTP_USER;if(!destination)return res.status(503).json({message:'No hay un correo de cotizaciones configurado'});await sendEmail(destination,`Solicitud de cotización: ${empresa||nombre}`,`Nombre: ${nombre}\nEmail: ${email}\nTeléfono: ${telefono||'No indicado'}\nEmpresa: ${empresa||'No indicada'}\n\n${mensaje}`);res.json({message:'Solicitud enviada. Nos pondremos en contacto contigo.'});}));
app.get('/api/dashboard',auth,asyncHandler(async(req,res)=>{const start=new Date();start.setHours(0,0,0,0);const end=new Date(start);end.setDate(end.getDate()+1);const [guardias,turnos,alertas,entradas,reportes,rondas,alertasLista,turnosLista]=await Promise.all([db.guardia.count({where:{estado:'Activo'}}),db.turno.count({where:{fecha:{gte:start,lt:end}}}),db.alerta.count({where:{estado:'Activa'}}),db.entrada.count({where:{estado:'Dentro'}}),db.reporte.count({where:{estado:'Abierto'}}),db.ronda.findMany({take:5,orderBy:{fecha_hora_inicio:'desc'}}),db.alerta.findMany({where:{estado:'Activa'},take:5,orderBy:{fecha:'desc'}}),db.turno.findMany({where:{fecha:{gte:start,lt:end}},take:5,orderBy:{hora_inicio:'asc'}})]);res.json({stats:{guardias,turnos,alertas,entradas,reportes,rondas:rondas.length},rondas,alertasLista,turnosLista});}));
app.get('/api/lookups/recintos',auth,asyncHandler(async(req,res)=>res.json(await db.recinto.findMany({where:{estado:'Activo'},select:{id:true,nombre:true,direccion:true},orderBy:{nombre:'asc'}}))));
app.get('/api/lookups/guardias',auth,asyncHandler(async(req,res)=>res.json(await db.guardia.findMany({where:{estado:'Activo'},select:{id:true,nombre:true,documento:true,recinto_id:true,recinto_nombre:true},orderBy:{nombre:'asc'}}))));
app.get('/api/users',auth,admin,asyncHandler(async(req,res)=>res.json((await db.user.findMany({orderBy:{created_at:'desc'}})).map(publicUser))));
app.post('/api/users/invite',auth,admin,asyncHandler(async(req,res)=>{const {password,send_invitation,...data}=req.body;if(!password||password.length<8)return res.status(400).json({message:'La contraseña debe tener al menos 8 caracteres'});const user=await db.user.create({data:{...data,password:await bcrypt.hash(password,12),email_verified:true,enabled:data.enabled??true}});if(send_invitation)await sendEmail(user.email,'Cuenta creada en GuardiaPro',`Tu cuenta fue creada. Ingresa con ${user.email} y la contraseña proporcionada por el administrador.`);res.status(201).json(publicUser(user));}));
app.put('/api/users/:id',auth,admin,asyncHandler(async(req,res)=>{const allowed=['full_name','email','role','rango','telefono','cargo','permisos','enabled'];const data=Object.fromEntries(Object.entries(req.body).filter(([key])=>allowed.includes(key)));res.json(publicUser(await db.user.update({where:{id:req.params.id},data})));}));
app.put('/api/users/:id/password',auth,admin,asyncHandler(async(req,res)=>{const {password}=req.body;if(!password||password.length<8)return res.status(400).json({message:'La contraseña debe tener al menos 8 caracteres'});await db.user.update({where:{id:req.params.id},data:{password:await bcrypt.hash(password,12),email_verified:true}});res.json({message:'Contraseña restablecida'});}));
app.delete('/api/users/:id',auth,admin,asyncHandler(async(req,res)=>{if(req.params.id===req.user!.id)return res.status(400).json({message:'No puedes eliminar tu usuario desde administración'});await db.user.delete({where:{id:req.params.id}});res.status(204).end();}));
const safeConfig=(c:any)=>({...c,smtp_password:undefined,telegram_bot_token:undefined,smtp_password_configured:!!c.smtp_password,telegram_token_configured:!!c.telegram_bot_token});
app.get('/api/config',auth,permit('configuracion'),asyncHandler(async(req,res)=>res.json(safeConfig(await db.configuracion.upsert({where:{id:1},update:{},create:{id:1}})))));app.put('/api/config',auth,admin,asyncHandler(async(req,res)=>{const allowed=['permitir_registro_publico','smtp_host','smtp_port','smtp_secure','smtp_user','smtp_password','mail_from','telegram_enabled','telegram_bot_token','telegram_chat_id','theme','brand_name','brand_subtitle','hero_title','hero_description','hero_footer','logo_url','icon_url','hero_image_url','public_page_enabled','public_banner_color','company_contact_enabled','company_contact_name','company_email','company_phone','company_address','company_website_url','company_title','company_description','company_services','quote_email'];const data:any=Object.fromEntries(Object.entries(req.body).filter(([key])=>allowed.includes(key)));if(!data.smtp_password)delete data.smtp_password;if(!data.telegram_bot_token)delete data.telegram_bot_token;const config=await db.configuracion.upsert({where:{id:1},update:data,create:{id:1,...data}});res.json(safeConfig(config));}));
app.post('/api/config/test-email',auth,admin,asyncHandler(async(req,res)=>{if(!req.body.email)return res.status(400).json({message:'Indica un email de destino'});await sendEmail(req.body.email,'Prueba SMTP GuardiaPro','La configuración SMTP funciona correctamente.');res.json({message:'Correo de prueba enviado'});}));
app.post('/api/config/test-telegram',auth,admin,asyncHandler(async(req,res)=>{await sendTelegram('<b>GuardiaPro</b>\nLa configuración de Telegram funciona correctamente.');res.json({message:'Mensaje de prueba enviado'});}));
app.use('/api/database',databaseAdmin);
app.put('/api/profile',auth,asyncHandler(async(req,res)=>{const {password,current_password,...data}=req.body;if(password){const me=await db.user.findUniqueOrThrow({where:{id:req.user!.id}});if(!me.password||!await bcrypt.compare(current_password,me.password))return res.status(400).json({message:'Contraseña actual incorrecta'});data.password=await bcrypt.hash(password,12);}res.json(publicUser(await db.user.update({where:{id:req.user!.id},data})));}));app.delete('/api/profile',auth,asyncHandler(async(req,res)=>{await db.user.delete({where:{id:req.user!.id}});res.status(204).end();}));
app.use('/api',auth,crud);
app.use('/api',(req,res)=>res.status(404).json({message:`Ruta API no encontrada: ${req.method} ${req.originalUrl}`}));
app.use((err:any,req:any,res:any,next:any)=>{console.error(err);res.status(err.name==='ZodError'?400:500).json({message:err.issues?.[0]?.message||err.message||'Error interno'});});
async function migrateCompatibility(){
  const existing=async(table:string)=>new Set((await db.$queryRawUnsafe<Array<{COLUMN_NAME:string}>>(
    `SELECT COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = '${table}'`
  )).map(column=>column.COLUMN_NAME));
  const userColumns=await existing('users');
  if(!userColumns.has('enabled'))await db.$executeRawUnsafe('ALTER TABLE users ADD COLUMN enabled BOOLEAN NOT NULL DEFAULT TRUE AFTER email_verified');
  const configColumns=await existing('configuracion');
  const configDefinitions:Record<string,string>={
    smtp_host:'VARCHAR(190) NULL',smtp_port:'SMALLINT UNSIGNED NOT NULL DEFAULT 587',smtp_secure:'BOOLEAN NOT NULL DEFAULT FALSE',
    smtp_user:'VARCHAR(190) NULL',smtp_password:'VARCHAR(255) NULL',mail_from:'VARCHAR(255) NULL',
    telegram_enabled:'BOOLEAN NOT NULL DEFAULT FALSE',telegram_bot_token:'VARCHAR(255) NULL',telegram_chat_id:'VARCHAR(100) NULL',
    theme:"VARCHAR(30) NOT NULL DEFAULT 'esmeralda'",brand_name:"VARCHAR(100) NOT NULL DEFAULT 'GuardiaPro'",brand_subtitle:"VARCHAR(150) NOT NULL DEFAULT 'Centro de operaciones'",
    hero_title:"VARCHAR(255) NOT NULL DEFAULT 'Seguridad conectada, decisiones claras.'",hero_description:'TEXT NULL',hero_footer:"VARCHAR(255) NOT NULL DEFAULT 'Protección visible. Gestión inteligente.'",
    logo_url:'MEDIUMTEXT NULL',icon_url:'MEDIUMTEXT NULL',hero_image_url:'MEDIUMTEXT NULL',public_page_enabled:'BOOLEAN NOT NULL DEFAULT FALSE',public_banner_color:"VARCHAR(20) NOT NULL DEFAULT '#e2e8f0'",
    company_contact_enabled:'BOOLEAN NOT NULL DEFAULT FALSE',company_contact_name:'VARCHAR(150) NULL',company_email:'VARCHAR(190) NULL',company_phone:'VARCHAR(40) NULL',company_address:'VARCHAR(255) NULL',company_website_url:'VARCHAR(500) NULL',
    company_title:"VARCHAR(255) NOT NULL DEFAULT 'Seguridad que inspira confianza'",company_description:'TEXT NULL',company_services:'TEXT NULL',quote_email:'VARCHAR(190) NULL'
  };
  for(const [column,definition] of Object.entries(configDefinitions)){
    if(!configColumns.has(column))await db.$executeRawUnsafe(`ALTER TABLE configuracion ADD COLUMN ${column} ${definition}`);
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
  server.listen(Number(process.env.PORT||4000),()=>console.log(`GuardiaPro API en http://localhost:${process.env.PORT||4000}`));
}
start().catch(error=>{console.error('No fue posible iniciar GuardiaPro:',error);process.exit(1)});
