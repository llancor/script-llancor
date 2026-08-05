import 'dotenv/config';
import bcrypt from 'bcryptjs';
import { db } from './lib.js';

async function main() {
  const [command, email, password] = process.argv.slice(2);
  if (command === 'list-users') {
    const users = await db.user.findMany({ select: { email: true, full_name: true, role: true, email_verified: true }, orderBy: { email: 'asc' } });
    console.table(users.map((u) => ({ email: u.email, nombre: u.full_name, rol: u.role, verificado: u.email_verified ? 'Sí' : 'No' })));
    return;
  }
  if (command === 'reset-password') {
    if (!email || !password) throw new Error('Uso: reset-password <email> <nueva contraseña>');
    if (password.length < 8) throw new Error('La contraseña debe tener al menos 8 caracteres');
    const user = await db.user.findUnique({ where: { email } });
    if (!user) throw new Error(`No existe un usuario con el email ${email}`);
    await db.user.update({ where: { email }, data: { password: await bcrypt.hash(password, 12), email_verified: true } });
    console.log(`Contraseña actualizada correctamente para ${email}`);
    return;
  }
  throw new Error('Comando válido: list-users | reset-password');
}
main().catch((e) => { console.error(`ERROR: ${e.message}`); process.exitCode = 1; }).finally(() => db.$disconnect());

