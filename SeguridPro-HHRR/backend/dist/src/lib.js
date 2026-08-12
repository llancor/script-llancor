import { PrismaClient } from '@prisma/client';
import jwt from 'jsonwebtoken';
import nodemailer from 'nodemailer';
import crypto from 'crypto';
export const db = new PrismaClient();
const secretKey = () => crypto.createHash('sha256').update(process.env.JWT_SECRET || '').digest();
export function encryptSecret(value) { const iv = crypto.randomBytes(12), cipher = crypto.createCipheriv('aes-256-gcm', secretKey(), iv), encrypted = Buffer.concat([cipher.update(value, 'utf8'), cipher.final()]); return ['v1', iv.toString('base64'), cipher.getAuthTag().toString('base64'), encrypted.toString('base64')].join(':'); }
export function decryptSecret(value) { if (!value)
    return ''; if (!value.startsWith('v1:'))
    return value; const [, iv, tag, data] = value.split(':'), decipher = crypto.createDecipheriv('aes-256-gcm', secretKey(), Buffer.from(iv, 'base64')); decipher.setAuthTag(Buffer.from(tag, 'base64')); return Buffer.concat([decipher.update(Buffer.from(data, 'base64')), decipher.final()]).toString('utf8'); }
export async function issueSession(user, meta = {}) {
    const expiresAt = new Date(Date.now() + 12 * 60 * 60_000);
    const session = await db.session.create({ data: { user_id: user.id, expires_at: expiresAt, ip_address: meta.ip, user_agent: meta.userAgent } });
    return jwt.sign({ id: user.id, role: user.role, permisos: user.permisos, sid: session.id }, process.env.JWT_SECRET, { expiresIn: '12h' });
}
export const publicUser = ({ password, failed_login_attempts, locked_until, ...user }) => user;
export async function audit(action, input = {}) {
    await db.auditLog.create({ data: { action, user_id: input.userId, entity: input.entity, entity_id: input.entityId, detail: input.detail, ip_address: input.ip, user_agent: input.userAgent } }).catch(error => console.error('No se pudo registrar auditoría', error));
}
export async function sendEmail(to, subject, text) {
    const config = await db.configuracion.findUnique({ where: { id: 1 } }).catch(() => null);
    const host = config?.smtp_host || process.env.SMTP_HOST;
    if (!host) {
        console.info(`[EMAIL DEV] ${to} | ${subject} | ${text}`);
        return;
    }
    const user = config?.smtp_user || process.env.SMTP_USER;
    const pass = config?.smtp_password || process.env.SMTP_PASS;
    const transport = nodemailer.createTransport({ host, port: Number(config?.smtp_port || process.env.SMTP_PORT || 587), secure: config?.smtp_secure || false, ...(user ? { auth: { user, pass } } : {}) });
    await transport.sendMail({ from: config?.mail_from || process.env.MAIL_FROM, to, subject, text });
}
export async function sendTelegram(text) {
    const config = await db.configuracion.findUnique({ where: { id: 1 } });
    if (!config?.telegram_enabled || !config.telegram_bot_token || !config.telegram_chat_id)
        return;
    const escapeHtml = (value) => String(value ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    const brand = String(config.brand_name || 'Seguridad').trim() || 'Seguridad';
    const response = await fetch(`https://api.telegram.org/bot${config.telegram_bot_token}/sendMessage`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ chat_id: config.telegram_chat_id, text: `<b>${escapeHtml(brand)}</b>\n${text}`, parse_mode: 'HTML' }) });
    if (!response.ok)
        throw new Error(`Telegram respondió ${response.status}`);
}
