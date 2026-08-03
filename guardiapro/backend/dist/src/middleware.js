import jwt from 'jsonwebtoken';
export function auth(req, res, next) {
    const token = req.headers.authorization?.replace('Bearer ', '');
    if (!token)
        return res.status(401).json({ message: 'Debes iniciar sesión' });
    try {
        req.user = jwt.verify(token, process.env.JWT_SECRET);
        next();
    }
    catch {
        return res.status(401).json({ message: 'Sesión inválida o expirada' });
    }
}
export const admin = (req, res, next) => req.user?.role === 'admin' ? next() : res.status(403).json({ message: 'Acceso solo para administradores' });
export const permit = (module) => (req, res, next) => req.user?.role === 'admin' || req.user?.permisos?.[module] === true ? next() : res.status(403).json({ message: `No tienes permiso para acceder a ${module}` });
export const asyncHandler = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);
