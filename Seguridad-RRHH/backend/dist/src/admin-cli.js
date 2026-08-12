import 'dotenv/config';
import bcrypt from 'bcryptjs';
import { db } from './lib.js';
const users = () => db.user.findMany({ orderBy: { email: 'asc' } });
async function selectUser(selector) {
    if (!selector)
        throw new Error('Indica el número o email del usuario');
    const list = await users(), index = Number(selector);
    const user = Number.isInteger(index) && index > 0 ? list[index - 1] : list.find(item => item.email.toLowerCase() === selector.toLowerCase());
    if (!user)
        throw new Error(`Usuario no encontrado: ${selector}`);
    return user;
}
async function main() {
    const [command, selector, value] = process.argv.slice(2);
    if (command === 'list-users') {
        const list = await users();
        console.table(list.map((u, index) => ({ '#': index + 1, email: u.email, nombre: u.full_name, rol: u.role, estado: u.enabled ? 'Activo' : 'Desactivado', bloqueo: u.locked_until && u.locked_until > new Date() ? `Hasta ${u.locked_until.toLocaleString('es-CL')}` : 'No', intentos: u.failed_login_attempts })));
        return;
    }
    if (command === 'reset-password') {
        if (!value || value.length < 10)
            throw new Error('La contraseña debe tener al menos 10 caracteres');
        const user = await selectUser(selector);
        await db.user.update({ where: { id: user.id }, data: { password: await bcrypt.hash(value, 12), email_verified: true, must_change_password: true, failed_login_attempts: 0, locked_until: null } });
        console.log(`Contraseña actualizada y bloqueo retirado para ${user.email}`);
        return;
    }
    if (command === 'unlock') {
        const user = await selectUser(selector);
        await db.user.update({ where: { id: user.id }, data: { failed_login_attempts: 0, locked_until: null } });
        console.log(`Bloqueo retirado para ${user.email}`);
        return;
    }
    if (command === 'set-enabled') {
        const user = await selectUser(selector), enabled = value === 'true';
        if (!['true', 'false'].includes(value || ''))
            throw new Error('Uso: set-enabled <número|email> <true|false>');
        if (!enabled && user.role === 'admin' && user.enabled && await db.user.count({ where: { role: 'admin', enabled: true } }) <= 1)
            throw new Error('No se puede desactivar el último administrador activo');
        await db.user.update({ where: { id: user.id }, data: { enabled, ...(!enabled ? { failed_login_attempts: 0, locked_until: null } : {}) } });
        console.log(`${user.email} quedó ${enabled ? 'activo' : 'desactivado'}`);
        return;
    }
    throw new Error('Comandos: list-users | reset-password | unlock | set-enabled');
}
main().catch(error => { console.error(`ERROR: ${error.message}`); process.exitCode = 1; }).finally(() => db.$disconnect());
