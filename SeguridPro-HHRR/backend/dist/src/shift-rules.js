import { db } from './lib.js';
const minutes = (value) => { const [h, m] = value.split(':').map(Number); return h * 60 + m; };
const duration = (start, end) => { const a = minutes(start), b = minutes(end); return (b > a ? b : b + 1440) - a; };
const at = (date, time, end = false) => { const d = new Date(date); const [h, m] = time.split(':').map(Number); d.setUTCHours(h, m, 0, 0); if (end && minutes(time) <= 0)
    d.setUTCDate(d.getUTCDate() + 1); return d; };
const interval = (date, start, end) => { const a = at(date, start), b = at(date, end); if (b <= a)
    b.setUTCDate(b.getUTCDate() + 1); return { start: a, end: b, hours: duration(start, end) / 60 }; };
export async function validateShifts(guardiaId, candidates, excludeId) {
    const minDate = new Date(Math.min(...candidates.map(x => x.fecha.getTime())) - 2 * 86400_000), maxDate = new Date(Math.max(...candidates.map(x => x.fecha.getTime())) + 9 * 86400_000);
    const existing = await db.turno.findMany({ where: { guardia_id: guardiaId, estado: { not: 'Cancelado' }, fecha: { gte: minDate, lte: maxDate }, ...(excludeId ? { id: { not: excludeId } } : {}) }, select: { id: true, fecha: true, hora_inicio: true, hora_fin: true, horas_colacion: true } });
    const all = [...existing, ...candidates.map((x, index) => ({ id: `nuevo-${index}`, ...x }))].map(x => ({ ...x, ...interval(x.fecha, x.hora_inicio, x.hora_fin) })).sort((a, b) => a.start.getTime() - b.start.getTime());
    for (let i = 1; i < all.length; i++) {
        if (all[i].start < all[i - 1].end)
            throw Object.assign(new Error('El guardia ya tiene un turno superpuesto en ese horario'), { status: 409 });
        const rest = (all[i].start.getTime() - all[i - 1].end.getTime()) / 3600_000;
        if (rest < 8)
            throw Object.assign(new Error(`Descanso insuficiente: se requieren 8 horas entre jornadas y solo hay ${rest.toFixed(1)}`), { status: 409 });
    }
    const effective = (shift) => Math.max(0, shift.hours - Math.max(0, Number(shift.horas_colacion) || 0));
    let maxWeeklyHours = 0;
    for (const candidate of candidates) {
        const day = new Date(candidate.fecha), weekday = (day.getUTCDay() + 6) % 7, start = new Date(day);
        start.setUTCDate(day.getUTCDate() - weekday);
        start.setUTCHours(0, 0, 0, 0);
        const end = new Date(start);
        end.setUTCDate(end.getUTCDate() + 7);
        const weekly = all.filter(x => x.start >= start && x.start < end).reduce((sum, x) => sum + effective(x), 0);
        maxWeeklyHours = Math.max(maxWeeklyHours, weekly);
    }
    return { hours: candidates.reduce((sum, x) => sum + Math.max(0, duration(x.hora_inicio, x.hora_fin) / 60 - Math.max(0, Number(x.horas_colacion) || 0)), 0), maxWeeklyHours, exceedsReference: maxWeeklyHours > 45 };
}
