USE guardiapro;
SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;
-- Contraseña del usuario: SeguridPro2026! (el seed Prisma genera el hash recomendado).
INSERT INTO users (id,full_name,email,password,role,rango,permisos,email_verified)
VALUES ('usr_admin_demo','Administrador SeguridPro','admin@seguridpro.cl','$2b$12$xCaxBD99uKB249dXuIsb0u9APtSBV2u8og7QWWiQN.Yea.D6lw16u','admin','supervisor',JSON_OBJECT('guardias',true,'turnos',true,'relevos',true,'rondas',true,'recintos',true,'entradas',true,'reportes',true,'alertas',true,'usuarios',true,'configuracion',true),true)
ON DUPLICATE KEY UPDATE full_name=VALUES(full_name);
INSERT INTO configuracion (id,permitir_registro_publico) VALUES (1,true) ON DUPLICATE KEY UPDATE permitir_registro_publico=VALUES(permitir_registro_publico);
INSERT INTO recintos (id,nombre,direccion,tipo,encargado,estado,created_by_id) VALUES
('rec_demo_001','Condominio Parque Norte','Av. Providencia 1840, Santiago','Condominio','Carolina Muñoz','Activo','usr_admin_demo');
INSERT INTO guardias (id,nombre,documento,telefono,email,rango,estado,fecha_ingreso,recinto_id,recinto_nombre,created_by_id) VALUES
('gua_demo_001','Matías Rojas','18.456.221-7','+56 9 5555 0101','matias@guardiapro.cl','guardia_senior','Activo','2025-03-15','rec_demo_001','Condominio Parque Norte','usr_admin_demo');
INSERT INTO turnos (id,guardia_id,guardia_nombre,tipo_turno,fecha,hora_inicio,hora_fin,ubicacion,estado,recinto_id,recinto_nombre,created_by_id) VALUES
('tur_demo_001','gua_demo_001','Matías Rojas','Manana',CURRENT_DATE(),'08:00','16:00','Acceso principal','Programado','rec_demo_001','Condominio Parque Norte','usr_admin_demo');
INSERT INTO rondas (id,guardia_id,guardia_nombre,fecha_hora_inicio,puntos_recorridos,estado,ruta,distancia_m,recinto_id,recinto_nombre,created_by_id) VALUES
('ron_demo_001','gua_demo_001','Matías Rojas',NOW(),'Acceso, estacionamientos y perímetro','En_curso',JSON_ARRAY(JSON_OBJECT('lat',-33.4372,'lng',-70.6506,'timestamp',NOW())),0,'rec_demo_001','Condominio Parque Norte','usr_admin_demo');
INSERT INTO entradas (id,visitante_nombre,visitante_documento,motivo,persona_visita,hora_entrada,guardia_id,guardia_nombre,estado,recinto_id,recinto_nombre,created_by_id) VALUES
('ent_demo_001','Daniela Soto','17.333.222-1','Visita residente','Depto. 804',NOW(),'gua_demo_001','Matías Rojas','Dentro','rec_demo_001','Condominio Parque Norte','usr_admin_demo');
INSERT INTO reportes (id,titulo,tipo,severidad,fecha,descripcion,ubicacion,guardia_id,guardia_nombre,estado,recinto_id,recinto_nombre,created_by_id) VALUES
('rep_demo_001','Luminaria exterior apagada','Mantenimiento','Media',NOW(),'Sector norte requiere revisión','Perímetro norte','gua_demo_001','Matías Rojas','Abierto','rec_demo_001','Condominio Parque Norte','usr_admin_demo');
INSERT INTO alertas (id,titulo,tipo,nivel,fecha,mensaje,ubicacion,guardia_id,estado,recinto_id,recinto_nombre,created_by_id) VALUES
('ale_demo_001','Puerta de servicio abierta','Acceso_no_autorizado','Advertencia',NOW(),'Sensor reporta apertura fuera de horario','Acceso de servicio','gua_demo_001','Activa','rec_demo_001','Condominio Parque Norte','usr_admin_demo');
