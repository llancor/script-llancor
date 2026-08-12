import { Router } from 'express';
import { z } from 'zod';
import { audit,db } from './lib.js';
import { asyncHandler } from './middleware.js';

export const miEmpresa=Router();
const companyAdmin=(req:any,res:any,next:any)=>req.user?.role==='admin'&&req.user?.empresa_id?next():res.status(403).json({message:'Acceso exclusivo del administrador de la empresa'});
const editable=z.object({nombre:z.string().min(2).max(191),rut:z.string().max(191).optional().nullable(),email:z.string().email().optional().nullable(),telefono:z.string().max(191).optional().nullable(),direccion:z.string().max(255).optional().nullable(),logo_url:z.string().optional().nullable(),website_url:z.string().url().optional().nullable().or(z.literal(''))});
miEmpresa.use(companyAdmin);
miEmpresa.get('/',asyncHandler(async(req,res)=>res.json(await db.empresa.findUniqueOrThrow({where:{id:req.user!.empresa_id},include:{_count:{select:{users:true,guardias:true,recintos:true,turnos:true}}}}))));
miEmpresa.put('/',asyncHandler(async(req,res)=>{const data=editable.parse(req.body);const item=await db.empresa.update({where:{id:req.user!.empresa_id},data:{...data,website_url:data.website_url||null}});await audit('editar_mi_empresa',{userId:req.user!.id,entity:'empresa',entityId:item.id,detail:{campos:Object.keys(data)}});res.json(item);}));
