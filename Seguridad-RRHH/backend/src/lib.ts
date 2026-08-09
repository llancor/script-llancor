import { PrismaClient } from '@prisma/client';
import jwt from 'jsonwebtoken';
import nodemailer from 'nodemailer';
export const db = new PrismaClient();
export async function issueSession(user:{id:string;role:string;permisos:unknown},meta:{ip?:string;userAgent?:string}={}){
  const expiresAt=new Date(Date.now()+12*60*60_000);
  const session=await db.session.create({data:{user_id:user.id,expires_at:expiresAt,ip_address:meta.ip,user_agent:meta.userAgent}});
  return jwt.sign({id:user.id,role:user.role,permisos:user.permisos,sid:session.id},process.env.JWT_SECRET!,{expiresIn:'12h'});
}
export const publicUser=({password,failed_login_attempts,locked_until,...user}:any)=>user;
export async function audit(action:string,input:{userId?:string;entity?:string;entityId?:string;detail?:unknown;ip?:string;userAgent?:string}={}){
  await db.auditLog.create({data:{action,user_id:input.userId,entity:input.entity,entity_id:input.entityId,detail:input.detail as any,ip_address:input.ip,user_agent:input.userAgent}}).catch(error=>console.error('No se pudo registrar auditoría',error));
}
export async function sendEmail(to:string, subject:string, text:string){
  const config=await db.configuracion.findUnique({where:{id:1}}).catch(()=>null);
  const host=config?.smtp_host||process.env.SMTP_HOST;
  if(!host){ console.info(`[EMAIL DEV] ${to} | ${subject} | ${text}`); return; }
  const user=config?.smtp_user||process.env.SMTP_USER;const pass=config?.smtp_password||process.env.SMTP_PASS;
  const transport=nodemailer.createTransport({host,port:Number(config?.smtp_port||process.env.SMTP_PORT||587),secure:config?.smtp_secure||false,...(user?{auth:{user,pass}}:{})});
  await transport.sendMail({from:config?.mail_from||process.env.MAIL_FROM,to,subject,text});
}
export async function sendTelegram(text:string){
  const config=await db.configuracion.findUnique({where:{id:1}});
  if(!config?.telegram_enabled||!config.telegram_bot_token||!config.telegram_chat_id)return;
  const response=await fetch(`https://api.telegram.org/bot${config.telegram_bot_token}/sendMessage`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({chat_id:config.telegram_chat_id,text,parse_mode:'HTML'})});
  if(!response.ok)throw new Error(`Telegram respondió ${response.status}`);
}
