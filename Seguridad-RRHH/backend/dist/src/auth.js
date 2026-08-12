import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { OAuth2Client } from 'google-auth-library';
import { z } from 'zod';
import jwt from 'jsonwebtoken';
import { audit, db, issueSession, publicUser, sendEmail, sendTelegram } from './lib.js';
import { auth, asyncHandler } from './middleware.js';
const router = Router();
const google = new OAuth2Client(process.env.GOOGLE_CLIENT_ID);
const otp = () => String(Math.floor(100000 + Math.random() * 900000));
async function createOtp(email, purpose) { const code = otp(); await db.otpToken.deleteMany({ where: { email, purpose } }); await db.otpToken.create({ data: { email, code: await bcrypt.hash(code, 8), purpose, expires_at: new Date(Date.now() + 15 * 60_000) } }); return code; }
router.post('/request-otp', asyncHandler(async (req, res) => { const { email } = z.object({ email: z.string().email() }).parse(req.body); const config = await db.configuracion.findUnique({ where: { id: 1 } }); if (!config?.permitir_registro_publico)
    return res.status(403).json({ message: 'El registro público está deshabilitado' }); const code = await createOtp(email, 'register'); await sendEmail(email, 'Código de verificación Seguridad-RRHH', `Tu código es ${code}. Vence en 15 minutos.`); res.json({ message: 'Código enviado' }); }));
router.post('/register', asyncHandler(async (req, res) => { const data = z.object({ full_name: z.string().min(2), email: z.string().email(), password: z.string().min(10), code: z.string().length(6) }).parse(req.body); const record = await db.otpToken.findFirst({ where: { email: data.email, purpose: 'register', expires_at: { gt: new Date() } }, orderBy: { created_at: 'desc' } }); if (!record || !await bcrypt.compare(data.code, record.code))
    return res.status(400).json({ message: 'Código inválido o vencido' }); const user = await db.user.create({ data: { full_name: data.full_name, email: data.email, password: await bcrypt.hash(data.password, 12), email_verified: true, permisos: {} } }); await db.otpToken.deleteMany({ where: { email: data.email } }); const token = await issueSession(user, { ip: req.ip, userAgent: req.get('user-agent') }); await audit('registro', { userId: user.id, ip: req.ip, userAgent: req.get('user-agent') }); res.status(201).json({ token, user: publicUser(user) }); }));
router.post('/login', asyncHandler(async (req, res) => { const { email, password } = z.object({ email: z.string().email(), password: z.string() }).parse(req.body); const [user, config] = await Promise.all([db.user.findUnique({ where: { email } }), db.configuracion.findUnique({ where: { id: 1 } })]); if (user?.locked_until && user.locked_until > new Date())
    return res.status(423).json({ message: `Cuenta bloqueada temporalmente. Intenta nuevamente después de ${user.locked_until.toLocaleTimeString('es-CL', { hour: '2-digit', minute: '2-digit' })}` }); const valid = !!user?.password && await bcrypt.compare(password, user.password); if (!valid) {
    if (user) {
        const max = Math.min(20, Math.max(1, config?.login_max_attempts || 5)), attempts = user.failed_login_attempts + 1, locked = attempts >= max ? new Date(Date.now() + Math.min(1440, Math.max(1, config?.login_lock_minutes || 15)) * 60_000) : null;
        await db.user.update({ where: { id: user.id }, data: { failed_login_attempts: locked ? 0 : attempts, locked_until: locked } });
        await audit('login_fallido', { userId: user.id, detail: { bloqueado: !!locked, intentos: attempts, limite: max }, ip: req.ip, userAgent: req.get('user-agent') });
        if (locked) {
            const text = `Bloqueo de cuenta por intentos fallidos\nUsuario: ${user.full_name}\nCorreo: ${user.email}\nIP: ${req.ip || 'No disponible'}\nBloqueada hasta: ${locked.toLocaleString('es-CL')}`;
            const destination = config?.notification_email || config?.smtp_user || process.env.SMTP_USER;
            if (config?.login_ban_email_enabled && destination)
                sendEmail(destination, 'Cuenta bloqueada por intentos fallidos', text).catch(console.error);
            if (config?.login_ban_telegram_enabled)
                sendTelegram(text).catch(console.error);
        }
    }
    return res.status(401).json({ message: 'Credenciales incorrectas' });
} if (!user.enabled)
    return res.status(403).json({ message: 'Tu cuenta está deshabilitada. Contacta al administrador' }); await db.user.update({ where: { id: user.id }, data: { failed_login_attempts: 0, locked_until: null, last_login_at: new Date() } }); const token = await issueSession(user, { ip: req.ip, userAgent: req.get('user-agent') }); await audit('login_exitoso', { userId: user.id, ip: req.ip, userAgent: req.get('user-agent') }); res.json({ token, user: publicUser(user) }); }));
router.post('/google', asyncHandler(async (req, res) => { const { credential } = z.object({ credential: z.string() }).parse(req.body); const ticket = await google.verifyIdToken({ idToken: credential, audience: process.env.GOOGLE_CLIENT_ID }); const p = ticket.getPayload(); if (!p?.email)
    return res.status(400).json({ message: 'Cuenta de Google inválida' }); let user = await db.user.findUnique({ where: { email: p.email } }); if (!user)
    user = await db.user.create({ data: { email: p.email, full_name: p.name || p.email, google_id: p.sub, email_verified: true, permisos: {} } }); if (!user.enabled)
    return res.status(403).json({ message: 'Cuenta deshabilitada' }); const token = await issueSession(user, { ip: req.ip, userAgent: req.get('user-agent') }); await audit('login_google', { userId: user.id, ip: req.ip, userAgent: req.get('user-agent') }); res.json({ token, user: publicUser(user) }); }));
router.post('/forgot-password', asyncHandler(async (req, res) => { const { email } = z.object({ email: z.string().email() }).parse(req.body); if (await db.user.findUnique({ where: { email } })) {
    const code = await createOtp(email, 'reset');
    await sendEmail(email, 'Recuperar contraseña Seguridad-RRHH', `Tu código es ${code}. Vence en 15 minutos.`);
} res.json({ message: 'Si la cuenta existe, recibirás un código' }); }));
router.post('/reset-password', asyncHandler(async (req, res) => { const data = z.object({ email: z.string().email(), code: z.string(), password: z.string().min(8) }).parse(req.body); const record = await db.otpToken.findFirst({ where: { email: data.email, purpose: 'reset', expires_at: { gt: new Date() } }, orderBy: { created_at: 'desc' } }); if (!record || !await bcrypt.compare(data.code, record.code))
    return res.status(400).json({ message: 'Código inválido o vencido' }); await db.user.update({ where: { email: data.email }, data: { password: await bcrypt.hash(data.password, 12) } }); await db.otpToken.deleteMany({ where: { email: data.email } }); res.json({ message: 'Contraseña actualizada' }); }));
router.get('/me', auth, asyncHandler(async (req, res) => res.json(publicUser(await db.user.findUniqueOrThrow({ where: { id: req.user.id } })))));
router.post('/logout', auth, asyncHandler(async (req, res) => { const token = req.headers.authorization?.replace('Bearer ', ''); const payload = jwt.decode(token || ''); if (payload?.sid)
    await db.session.updateMany({ where: { id: payload.sid, user_id: req.user.id }, data: { revoked_at: new Date() } }); await audit('logout', { userId: req.user.id, ip: req.ip, userAgent: req.get('user-agent') }); res.status(204).end(); }));
router.post('/logout-all', auth, asyncHandler(async (req, res) => { await db.session.updateMany({ where: { user_id: req.user.id, revoked_at: null }, data: { revoked_at: new Date() } }); await audit('logout_todas_sesiones', { userId: req.user.id, ip: req.ip, userAgent: req.get('user-agent') }); res.status(204).end(); }));
export default router;
