import { Router } from 'express';
import { db, sendTelegram } from './lib.js';
import { asyncHandler } from './middleware.js';
const allowed = ['guardia', 'recinto', 'turno', 'ronda', 'entrada', 'reporte', 'alerta'];
const dateFields = { guardia: ['fecha_ingreso'], turno: ['fecha'], ronda: ['fecha_hora_inicio', 'fecha_hora_fin'], entrada: ['hora_entrada', 'hora_salida'], reporte: ['fecha'], alerta: ['fecha'] };
const normalize = (model, body) => Object.fromEntries(Object.entries(body).map(([k, v]) => [k, dateFields[model]?.includes(k) && v ? new Date(v) : v]));
export const crud = Router();
crud.param('model', (req, res, next, model) => allowed.includes(model) ? next() : res.status(404).json({ message: 'Recurso no encontrado' }));
crud.use('/:model', (req, res, next) => { const permission = `${req.params.model}s`; if (req.user?.role === 'admin' || req.user?.permisos?.[permission] === true)
    return next(); return res.status(403).json({ message: 'No tienes permiso para acceder a este módulo' }); });
crud.get('/:model', asyncHandler(async (req, res) => { const model = req.params.model; const { q, page = '1', limit = '50', ...filters } = req.query; const where = {}; for (const [k, v] of Object.entries(filters))
    if (v)
        where[k] = v; const searchable = { guardia: ['nombre', 'documento'], recinto: ['nombre', 'direccion'], turno: ['guardia_nombre', 'ubicacion'], ronda: ['guardia_nombre', 'novedades'], entrada: ['visitante_nombre', 'visitante_documento'], reporte: ['titulo', 'descripcion'], alerta: ['titulo', 'mensaje'] }; if (q)
    where.OR = searchable[model].map(f => ({ [f]: { contains: q, mode: 'insensitive' } })); const client = db[model]; const [data, total] = await Promise.all([client.findMany({ where, orderBy: { created_at: 'desc' }, skip: (+page - 1) * (+limit), take: +limit }), client.count({ where })]); res.json({ data, total, page: +page }); }));
crud.get('/:model/:id', asyncHandler(async (req, res) => res.json(await db[req.params.model].findUniqueOrThrow({ where: { id: req.params.id } }))));
crud.post('/:model', asyncHandler(async (req, res) => { const data = normalize(req.params.model, { ...req.body, created_by_id: req.user.id }); const item = await db[req.params.model].create({ data }); req.app.get('io')?.emit(`${req.params.model}:created`, item); if (req.params.model === 'alerta')
    sendTelegram(`<b>🚨 ${item.titulo}</b>\nNivel: ${item.nivel}\n${item.mensaje || ''}\n📍 ${item.ubicacion || 'Sin ubicación'}`).catch(error => console.error('No se pudo notificar por Telegram:', error)); res.status(201).json(item); }));
crud.put('/:model/:id', asyncHandler(async (req, res) => { const data = normalize(req.params.model, req.body); delete data.id; delete data.created_at; delete data.updated_at; delete data.created_by_id; const item = await db[req.params.model].update({ where: { id: req.params.id }, data }); req.app.get('io')?.emit(`${req.params.model}:updated`, item); res.json(item); }));
crud.delete('/:model/:id', asyncHandler(async (req, res) => { await db[req.params.model].delete({ where: { id: req.params.id } }); res.status(204).end(); }));
