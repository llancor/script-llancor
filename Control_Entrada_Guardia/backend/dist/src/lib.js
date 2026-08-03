import { PrismaClient } from '@prisma/client';
import jwt from 'jsonwebtoken';
import nodemailer from 'nodemailer';
export const db = new PrismaClient();
export const signToken = (user) => jwt.sign(user, process.env.JWT_SECRET, { expiresIn: '12h' });
export const publicUser = ({ password, ...user }) => user;
export async function sendEmail(to, subject, text) {
    if (!process.env.SMTP_HOST) {
        console.info(`[EMAIL DEV] ${to} | ${subject} | ${text}`);
        return;
    }
    const transport = nodemailer.createTransport({ host: process.env.SMTP_HOST, port: Number(process.env.SMTP_PORT || 587), secure: false, auth: { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS } });
    await transport.sendMail({ from: process.env.MAIL_FROM, to, subject, text });
}
