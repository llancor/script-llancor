import jwt from 'jsonwebtoken';
import { db } from './lib.js';
export async function auth(req, res, next) {
    const token = req.headers.authorization?.replace('Bearer ', '');
    if (!token)
        return res.status(401).json({ message: 'Debes iniciar sesión' });
    try {
        const payload = jwt.verify(token, process.env.JWT_SECRET);
        if (!payload.sid)
            return res.status(401).json({ message: 'Sesión antigua no válida. Inicia sesión nuevamente' });
        const [current, session] = await Promise.all([db.user.findUnique({ where: { id: payload.id }, select: { id: true, role: true, permisos: true, guardia_id: true, enabled: true, must_change_password: true } }), db.session.findUnique({ where: { id: payload.sid } })]);
        if (!current?.enabled)
            return res.status(401).json({ message: 'Cuenta inexistente o deshabilitada' });
        if (!session || session.user_id !== current.id || session.revoked_at || session.expires_at <= new Date())
            return res.status(401).json({ message: 'Sesión revocada o expirada' });
        req.user = { id: current.id, role: current.role, permisos: current.permisos, guardia_id: current.guardia_id || undefined, must_change_password: current.must_change_password };
        if (current.must_change_password && !['/api/profile', '/api/auth/me', '/api/auth/logout'].includes(req.originalUrl.split('?')[0]))
            return res.status(403).json({ message: 'Debes cambiar tu contraseña temporal para continuar' });
        next();
    }
    catch {
        return res.status(401).json({ message: 'Sesión inválida o expirada' });
    }
}
export const admin = (req, res, next) => req.user?.role === 'admin' ? next() : res.status(403).json({ message: 'Acceso solo para administradores' });
export const permit = (module) => (req, res, next) => req.user?.role === 'admin' || req.user?.permisos?.[module] === true ? next() : res.status(403).json({ message: `No tienes permiso para acceder a ${module}` });
export const asyncHandler = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);
