import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { OAuth2Client } from 'google-auth-library';
import { z } from 'zod';
import { db, publicUser, sendEmail, signToken } from './lib.js';
import { auth, asyncHandler } from './middleware.js';
const router = Router();
const google = new OAuth2Client(process.env.GOOGLE_CLIENT_ID);
const otp = () => String(Math.floor(100000 + Math.random() * 900000));
async function createOtp(email, purpose) { const code = otp(); await db.otpToken.deleteMany({ where: { email, purpose } }); await db.otpToken.create({ data: { email, code: await bcrypt.hash(code, 8), purpose, expires_at: new Date(Date.now() + 15 * 60_000) } }); return code; }
router.post('/request-otp', asyncHandler(async (req, res) => { const { email } = z.object({ email: z.string().email() }).parse(req.body); const config = await db.configuracion.findUnique({ where: { id: 1 } }); if (!config?.permitir_registro_publico)
    return res.status(403).json({ message: 'El registro público está deshabilitado' }); const code = await createOtp(email, 'register'); await sendEmail(email, 'Código de verificación GuardiaPro', `Tu código es ${code}. Vence en 15 minutos.`); res.json({ message: 'Código enviado' }); }));
router.post('/register', asyncHandler(async (req, res) => { const data = z.object({ full_name: z.string().min(2), email: z.string().email(), password: z.string().min(8), code: z.string().length(6) }).parse(req.body); const record = await db.otpToken.findFirst({ where: { email: data.email, purpose: 'register', expires_at: { gt: new Date() } }, orderBy: { created_at: 'desc' } }); if (!record || !await bcrypt.compare(data.code, record.code))
    return res.status(400).json({ message: 'Código inválido o vencido' }); const user = await db.user.create({ data: { full_name: data.full_name, email: data.email, password: await bcrypt.hash(data.password, 12), email_verified: true, permisos: {} } }); await db.otpToken.deleteMany({ where: { email: data.email } }); res.status(201).json({ token: signToken(user), user: publicUser(user) }); }));
router.post('/login', asyncHandler(async (req, res) => { const { email, password } = z.object({ email: z.string().email(), password: z.string() }).parse(req.body); const user = await db.user.findUnique({ where: { email } }); if (!user?.password || !await bcrypt.compare(password, user.password))
    return res.status(401).json({ message: 'Credenciales incorrectas' }); if (!user.enabled)
    return res.status(403).json({ message: 'Tu cuenta está deshabilitada. Contacta al administrador' }); res.json({ token: signToken(user), user: publicUser(user) }); }));
router.post('/google', asyncHandler(async (req, res) => { const { credential } = z.object({ credential: z.string() }).parse(req.body); const ticket = await google.verifyIdToken({ idToken: credential, audience: process.env.GOOGLE_CLIENT_ID }); const p = ticket.getPayload(); if (!p?.email)
    return res.status(400).json({ message: 'Cuenta de Google inválida' }); let user = await db.user.findUnique({ where: { email: p.email } }); if (!user)
    user = await db.user.create({ data: { email: p.email, full_name: p.name || p.email, google_id: p.sub, email_verified: true, permisos: {} } }); res.json({ token: signToken(user), user: publicUser(user) }); }));
router.post('/forgot-password', asyncHandler(async (req, res) => { const { email } = z.object({ email: z.string().email() }).parse(req.body); if (await db.user.findUnique({ where: { email } })) {
    const code = await createOtp(email, 'reset');
    await sendEmail(email, 'Recuperar contraseña GuardiaPro', `Tu código es ${code}. Vence en 15 minutos.`);
} res.json({ message: 'Si la cuenta existe, recibirás un código' }); }));
router.post('/reset-password', asyncHandler(async (req, res) => { const data = z.object({ email: z.string().email(), code: z.string(), password: z.string().min(8) }).parse(req.body); const record = await db.otpToken.findFirst({ where: { email: data.email, purpose: 'reset', expires_at: { gt: new Date() } }, orderBy: { created_at: 'desc' } }); if (!record || !await bcrypt.compare(data.code, record.code))
    return res.status(400).json({ message: 'Código inválido o vencido' }); await db.user.update({ where: { email: data.email }, data: { password: await bcrypt.hash(data.password, 12) } }); await db.otpToken.deleteMany({ where: { email: data.email } }); res.json({ message: 'Contraseña actualizada' }); }));
router.get('/me', auth, asyncHandler(async (req, res) => res.json(publicUser(await db.user.findUniqueOrThrow({ where: { id: req.user.id } })))));
export default router;
