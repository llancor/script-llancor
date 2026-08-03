import { Request,Response,NextFunction } from 'express';
import jwt from 'jsonwebtoken';
export function auth(req:Request,res:Response,next:NextFunction){
  const token=req.headers.authorization?.replace('Bearer ','');
  if(!token) return res.status(401).json({message:'Debes iniciar sesión'});
  try{req.user=jwt.verify(token,process.env.JWT_SECRET!) as any; next();}catch{return res.status(401).json({message:'Sesión inválida o expirada'});}
}
export const admin=(req:Request,res:Response,next:NextFunction)=>req.user?.role==='admin'?next():res.status(403).json({message:'Acceso solo para administradores'});
export const asyncHandler=(fn:any)=>(req:Request,res:Response,next:NextFunction)=>Promise.resolve(fn(req,res,next)).catch(next);

