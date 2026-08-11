import { PrismaClient } from '@prisma/client';
import bcrypt from 'bcryptjs';
const db = new PrismaClient();
const main = async () => {
  const initial=process.env.INITIAL_ADMIN_PASSWORD;
  if(!initial)throw new Error('INITIAL_ADMIN_PASSWORD es obligatoria para crear el administrador');
  const password = await bcrypt.hash(initial, 12);
  const email=process.env.INITIAL_ADMIN_EMAIL||'admin@seguridad.cl';
  await db.user.upsert({ where:{email}, update:{role:'superadmin',empresa_id:null,permisos:{empresas:true}}, create:{full_name:'Propietario de la plataforma',email,password,role:'superadmin',email_verified:true,must_change_password:true,permisos:{empresas:true}}});
  await db.configuracion.upsert({where:{id:1},update:{},create:{id:1,permitir_registro_publico:true}});
};
main().finally(()=>db.$disconnect());
