import { PrismaClient } from '@prisma/client';
import bcrypt from 'bcryptjs';
const db = new PrismaClient();
const main = async () => {
    const password = await bcrypt.hash('GuardiaPro2026!', 12);
    await db.user.upsert({ where: { email: 'admin@guardiapro.cl' }, update: {}, create: { full_name: 'Administrador GuardiaPro', email: 'admin@guardiapro.cl', password, role: 'admin', email_verified: true, permisos: { guardias: true, turnos: true, relevos: true, rondas: true, recintos: true, entradas: true, reportes: true, alertas: true, usuarios: true, configuracion: true } } });
    await db.configuracion.upsert({ where: { id: 1 }, update: {}, create: { id: 1, permitir_registro_publico: true } });
};
main().finally(() => db.$disconnect());
