USE bastcontrol;
SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Repara los datos demostrativos si fueron importados por un cliente latin1.
UPDATE guardias SET nombre = 'Matías Rojas' WHERE id = 'gua_demo_001';
UPDATE turnos SET guardia_nombre = 'Matías Rojas' WHERE guardia_id = 'gua_demo_001';
UPDATE rondas SET guardia_nombre = 'Matías Rojas' WHERE guardia_id = 'gua_demo_001';
UPDATE entradas SET guardia_nombre = 'Matías Rojas' WHERE guardia_id = 'gua_demo_001';
UPDATE reportes SET guardia_nombre = 'Matías Rojas' WHERE guardia_id = 'gua_demo_001';
UPDATE recintos SET encargado = 'Carolina Muñoz' WHERE id = 'rec_demo_001';
UPDATE rondas SET puntos_recorridos = 'Acceso, estacionamientos y perímetro' WHERE id = 'ron_demo_001';
UPDATE reportes
SET descripcion = 'Sector norte requiere revisión', ubicacion = 'Perímetro norte'
WHERE id = 'rep_demo_001';
