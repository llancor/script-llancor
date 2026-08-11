import { randomBytes } from 'crypto';
import { resolve4,resolve6,resolveCname,resolveTxt } from 'dns/promises';
import { Router } from 'express';
import { z } from 'zod';
import { audit,db } from './lib.js';
import { asyncHandler,superadmin } from './middleware.js';

export const dominios=Router();
const cleanHost=(value:unknown)=>String(value||'').trim().toLowerCase().replace(/^https?:\/\//,'').split('/')[0].replace(/:\d+$/,'').replace(/\.$/,'');
const domainSchema=z.string().transform(cleanHost).refine(value=>/^(?=.{4,253}$)(?!-)(?:[a-z0-9-]+\.)+[a-z]{2,63}$/.test(value),'Dominio no válido');
const inputSchema=z.object({empresa_id:z.string().min(1),dominio:domainSchema,tipo:z.enum(['Dominio','Subdominio','SubdominioSistema']).default('Dominio'),principal:z.boolean().default(false),destino_esperado:z.string().trim().optional().nullable()});

async function dnsState(item:{dominio:string;token_verificacion:string;destino_esperado:string|null}){
  const expected=item.destino_esperado||process.env.PUBLIC_IP||'';
  const [ipv4,ipv6,cnames,txt]=await Promise.all([
    resolve4(item.dominio).catch(():string[]=>[]),resolve6(item.dominio).catch(():string[]=>[]),resolveCname(item.dominio).catch(():string[]=>[]),
    resolveTxt(`_seguridadpro-verification.${item.dominio}`).then(rows=>rows.map(parts=>parts.join(''))).catch(():string[]=>[])
  ]);
  const targetOk=!expected||ipv4.includes(expected)||ipv6.includes(expected)||cnames.some(value=>value.replace(/\.$/,'')===expected.replace(/\.$/,''));
  const tokenOk=txt.includes(item.token_verificacion);
  return{expected,ipv4,ipv6,cnames,txt_verified:tokenOk,target_verified:targetOk,verified:targetOk&&tokenOk};
}

dominios.get('/',superadmin,asyncHandler(async(req,res)=>{const empresaId=String(req.query.empresa_id||'');res.json(await db.empresaDominio.findMany({where:empresaId?{empresa_id:empresaId}:{},include:{empresa:{select:{nombre:true,slug:true,estado:true}}},orderBy:[{empresa_id:'asc'},{principal:'desc'},{dominio:'asc'}]}))}));
dominios.post('/',superadmin,asyncHandler(async(req,res)=>{const data=inputSchema.parse(req.body);await db.empresa.findUniqueOrThrow({where:{id:data.empresa_id}});const token=`seguridadpro-${randomBytes(18).toString('hex')}`;const item=await db.$transaction(async tx=>{if(data.principal)await tx.empresaDominio.updateMany({where:{empresa_id:data.empresa_id},data:{principal:false}});return tx.empresaDominio.create({data:{...data,token_verificacion:token,destino_esperado:data.destino_esperado||process.env.PUBLIC_IP||null}})});await audit('crear_dominio',{userId:req.user!.id,entity:'empresa_dominio',entityId:item.id,detail:{dominio:item.dominio}});res.status(201).json(item);}));
dominios.put('/:id',superadmin,asyncHandler(async(req,res)=>{const data=inputSchema.partial().omit({empresa_id:true}).parse(req.body);const current=await db.empresaDominio.findUniqueOrThrow({where:{id:req.params.id}});const item=await db.$transaction(async tx=>{if(data.principal)await tx.empresaDominio.updateMany({where:{empresa_id:current.empresa_id},data:{principal:false}});return tx.empresaDominio.update({where:{id:current.id},data:{...data,...(data.dominio&&data.dominio!==current.dominio?{estado:'Pendiente',verificado_at:null,ssl_estado:'Pendiente'}:{})}})});res.json(item);}));
dominios.post('/:id/verificar',superadmin,asyncHandler(async(req,res)=>{const item=await db.empresaDominio.findUniqueOrThrow({where:{id:req.params.id}});await db.empresaDominio.update({where:{id:item.id},data:{estado:'Verificando',ultimo_error:null}});const result=await dnsState(item);const updated=await db.empresaDominio.update({where:{id:item.id},data:result.verified?{estado:'Activo',verificado_at:new Date(),ultimo_error:null}:{estado:'Error_DNS',ultimo_error:!result.txt_verified?'Falta el registro TXT de verificación':'El dominio no apunta al destino esperado'}});res.json({dominio:updated,dns:result});}));
dominios.post('/:id/suspender',superadmin,asyncHandler(async(req,res)=>res.json(await db.empresaDominio.update({where:{id:req.params.id},data:{estado:'Suspendido'}}))));
dominios.delete('/:id',superadmin,asyncHandler(async(req,res)=>{await db.empresaDominio.delete({where:{id:req.params.id}});res.status(204).end()}));

export const resolverDominio=asyncHandler(async(req,res)=>{const host=domainSchema.parse(req.query.host||req.hostname);const item=await db.empresaDominio.findFirst({where:{dominio:host,estado:'Activo',empresa:{estado:'Activa',OR:[{vence_at:null},{vence_at:{gt:new Date()}}]}},include:{empresa:{select:{id:true,nombre:true,slug:true,logo_url:true,modulos:true}}}});if(!item)return res.status(404).json({message:'Dominio no registrado o inactivo'});res.json({dominio:item.dominio,principal:item.principal,empresa:item.empresa});});
