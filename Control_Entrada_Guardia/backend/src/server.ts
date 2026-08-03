import 'dotenv/config';
import express from 'express'; import cors from 'cors'; import helmet from 'helmet'; import morgan from 'morgan';
import { createServer } from 'http'; import { Server } from 'socket.io'; import rateLimit from 'express-rate-limit'; import bcrypt from 'bcryptjs';
import authRoutes from './auth.js'; import { crud } from './crud.js'; import { auth,admin,asyncHandler } from './middleware.js'; import { db,publicUser,sendEmail,sendTelegram } from './lib.js';
const app=express();const server=createServer(app);const io=new Server(server,{cors:{origin:process.env.FRONTEND_URL}});app.set('io',io);
app.use(helmet());app.use(cors({origin:process.env.FRONTEND_URL}));app.use(express.json({limit:'1mb'}));app.use(morgan('dev'));app.use('/api/auth',rateLimit({windowMs:60_000,limit:30}),authRoutes);
app.get('/api/health',(req,res)=>res.json({status:'ok'}));
app.get('/api/dashboard',auth,asyncHandler(async(req,res)=>{const start=new Date();start.setHours(0,0,0,0);const end=new Date(start);end.setDate(end.getDate()+1);const [guardias,turnos,alertas,entradas,reportes,rondas,alertasLista,turnosLista]=await Promise.all([db.guardia.count({where:{estado:'Activo'}}),db.turno.count({where:{fecha:{gte:start,lt:end}}}),db.alerta.count({where:{estado:'Activa'}}),db.entrada.count({where:{estado:'Dentro'}}),db.reporte.count({where:{estado:'Abierto'}}),db.ronda.findMany({take:5,orderBy:{fecha_hora_inicio:'desc'}}),db.alerta.findMany({where:{estado:'Activa'},take:5,orderBy:{fecha:'desc'}}),db.turno.findMany({where:{fecha:{gte:start,lt:end}},take:5,orderBy:{hora_inicio:'asc'}})]);res.json({stats:{guardias,turnos,alertas,entradas,reportes,rondas:rondas.length},rondas,alertasLista,turnosLista});}));
app.get('/api/users',auth,admin,asyncHandler(async(req,res)=>res.json((await db.user.findMany({orderBy:{created_at:'desc'}})).map(publicUser))));
app.post('/api/users/invite',auth,admin,asyncHandler(async(req,res)=>{const {password,send_invitation,...data}=req.body;if(!password||password.length<8)return res.status(400).json({message:'La contraseña debe tener al menos 8 caracteres'});const user=await db.user.create({data:{...data,password:await bcrypt.hash(password,12),email_verified:true,enabled:data.enabled??true}});if(send_invitation)await sendEmail(user.email,'Cuenta creada en GuardiaPro',`Tu cuenta fue creada. Ingresa con ${user.email} y la contraseña proporcionada por el administrador.`);res.status(201).json(publicUser(user));}));
app.put('/api/users/:id',auth,admin,asyncHandler(async(req,res)=>{const allowed=['full_name','email','role','rango','telefono','cargo','permisos','enabled'];const data=Object.fromEntries(Object.entries(req.body).filter(([key])=>allowed.includes(key)));res.json(publicUser(await db.user.update({where:{id:req.params.id},data})));}));
app.put('/api/users/:id/password',auth,admin,asyncHandler(async(req,res)=>{const {password}=req.body;if(!password||password.length<8)return res.status(400).json({message:'La contraseña debe tener al menos 8 caracteres'});await db.user.update({where:{id:req.params.id},data:{password:await bcrypt.hash(password,12),email_verified:true}});res.json({message:'Contraseña restablecida'});}));
app.delete('/api/users/:id',auth,admin,asyncHandler(async(req,res)=>{if(req.params.id===req.user!.id)return res.status(400).json({message:'No puedes eliminar tu usuario desde administración'});await db.user.delete({where:{id:req.params.id}});res.status(204).end();}));
const safeConfig=(c:any)=>({...c,smtp_password:undefined,telegram_bot_token:undefined,smtp_password_configured:!!c.smtp_password,telegram_token_configured:!!c.telegram_bot_token});
app.get('/api/config',auth,asyncHandler(async(req,res)=>res.json(safeConfig(await db.configuracion.upsert({where:{id:1},update:{},create:{id:1}})))));app.put('/api/config',auth,admin,asyncHandler(async(req,res)=>{const allowed=['permitir_registro_publico','smtp_host','smtp_port','smtp_secure','smtp_user','smtp_password','mail_from','telegram_enabled','telegram_bot_token','telegram_chat_id'];const data:any=Object.fromEntries(Object.entries(req.body).filter(([key])=>allowed.includes(key)));if(!data.smtp_password)delete data.smtp_password;if(!data.telegram_bot_token)delete data.telegram_bot_token;const config=await db.configuracion.upsert({where:{id:1},update:data,create:{id:1,...data}});res.json(safeConfig(config));}));
app.post('/api/config/test-email',auth,admin,asyncHandler(async(req,res)=>{if(!req.body.email)return res.status(400).json({message:'Indica un email de destino'});await sendEmail(req.body.email,'Prueba SMTP GuardiaPro','La configuración SMTP funciona correctamente.');res.json({message:'Correo de prueba enviado'});}));
app.post('/api/config/test-telegram',auth,admin,asyncHandler(async(req,res)=>{await sendTelegram('<b>GuardiaPro</b>\nLa configuración de Telegram funciona correctamente.');res.json({message:'Mensaje de prueba enviado'});}));
app.put('/api/profile',auth,asyncHandler(async(req,res)=>{const {password,current_password,...data}=req.body;if(password){const me=await db.user.findUniqueOrThrow({where:{id:req.user!.id}});if(!me.password||!await bcrypt.compare(current_password,me.password))return res.status(400).json({message:'Contraseña actual incorrecta'});data.password=await bcrypt.hash(password,12);}res.json(publicUser(await db.user.update({where:{id:req.user!.id},data})));}));app.delete('/api/profile',auth,asyncHandler(async(req,res)=>{await db.user.delete({where:{id:req.user!.id}});res.status(204).end();}));
app.use('/api',auth,crud);
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
    telegram_enabled:'BOOLEAN NOT NULL DEFAULT FALSE',telegram_bot_token:'VARCHAR(255) NULL',telegram_chat_id:'VARCHAR(100) NULL'
  };
  for(const [column,definition] of Object.entries(configDefinitions)){
    if(!configColumns.has(column))await db.$executeRawUnsafe(`ALTER TABLE configuracion ADD COLUMN ${column} ${definition}`);
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
  await migrateCompatibility();
  server.listen(Number(process.env.PORT||4000),()=>console.log(`GuardiaPro API en http://localhost:${process.env.PORT||4000}`));
}
start().catch(error=>{console.error('No fue posible iniciar GuardiaPro:',error);process.exit(1)});
