import { PrismaClient } from '@prisma/client';
import jwt from 'jsonwebtoken';
import nodemailer from 'nodemailer';
export const db = new PrismaClient();
export const signToken = (user) => jwt.sign(user, process.env.JWT_SECRET, { expiresIn: '12h' });
export const publicUser = ({ password, ...user }) => user;
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
    const response = await fetch(`https://api.telegram.org/bot${config.telegram_bot_token}/sendMessage`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ chat_id: config.telegram_chat_id, text, parse_mode: 'HTML' }) });
    if (!response.ok)
        throw new Error(`Telegram respondió ${response.status}`);
}
