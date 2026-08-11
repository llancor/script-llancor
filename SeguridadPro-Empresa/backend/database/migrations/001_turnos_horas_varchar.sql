USE seguridad_rrhh;

-- Prisma modela las horas de turno como texto HH:MM/HH:MM:SS.
-- MySQL convierte automáticamente los valores TIME existentes sin perderlos.
ALTER TABLE turnos
  MODIFY COLUMN hora_inicio VARCHAR(8) NOT NULL,
  MODIFY COLUMN hora_fin VARCHAR(8) NOT NULL;

