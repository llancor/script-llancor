CREATE DATABASE IF NOT EXISTS guardiapro CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE guardiapro;
SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE users (
  id VARCHAR(30) PRIMARY KEY,
  full_name VARCHAR(150) NOT NULL,
  email VARCHAR(190) NOT NULL,
  password VARCHAR(255) NULL,
  role ENUM('admin','jefe_turno','guardia','establecimiento') NOT NULL DEFAULT 'guardia',
  rango ENUM('supervisor','guardia_senior','guardia','cabo','conserje','nochero') NULL,
  telefono VARCHAR(30) NULL, cargo VARCHAR(120) NULL,
  permisos JSON NOT NULL,
  email_verified BOOLEAN NOT NULL DEFAULT FALSE,
  enabled BOOLEAN NOT NULL DEFAULT TRUE,
  google_id VARCHAR(190) NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_users_email (email), UNIQUE KEY uq_users_google (google_id)
) ENGINE=InnoDB;

CREATE TABLE recintos (
  id VARCHAR(30) PRIMARY KEY, nombre VARCHAR(150) NOT NULL, direccion VARCHAR(255) NOT NULL,
  tipo ENUM('Condominio','Departamento','Edificio','Complejo','Urbanizacion','Oficina','Otro') NOT NULL,
  encargado VARCHAR(150), email VARCHAR(190), telefono VARCHAR(30), observaciones TEXT,
  estado ENUM('Activo','Inactivo') NOT NULL DEFAULT 'Activo', created_by_id VARCHAR(30) NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY idx_recintos_estado (estado), KEY idx_recintos_created_by (created_by_id),
  CONSTRAINT fk_recintos_creator FOREIGN KEY (created_by_id) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE guardias (
  id VARCHAR(30) PRIMARY KEY, nombre VARCHAR(150) NOT NULL, documento VARCHAR(80) NOT NULL,
  telefono VARCHAR(30), email VARCHAR(190),
  rango ENUM('supervisor','guardia_senior','guardia','cabo','conserje','nochero') NOT NULL DEFAULT 'guardia',
  estado ENUM('Activo','Inactivo','Licencia','Suspendido') NOT NULL DEFAULT 'Activo',
  fecha_ingreso DATE, foto_url MEDIUMTEXT NULL, recinto_id VARCHAR(30) NULL, recinto_nombre VARCHAR(150), created_by_id VARCHAR(30) NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_guardias_documento (documento), KEY idx_guardias_recinto (recinto_id), KEY idx_guardias_estado (estado), KEY idx_guardias_created_by (created_by_id),
  CONSTRAINT fk_guardias_recinto FOREIGN KEY (recinto_id) REFERENCES recintos(id) ON DELETE SET NULL,
  CONSTRAINT fk_guardias_creator FOREIGN KEY (created_by_id) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE turnos (
  id VARCHAR(30) PRIMARY KEY, guardia_id VARCHAR(30) NULL, guardia_nombre VARCHAR(150) NOT NULL,
  tipo_turno ENUM('Manana','Tarde','Dia','Noche','Personalizado') NOT NULL, fecha DATE NOT NULL, hora_inicio VARCHAR(8) NOT NULL, hora_fin VARCHAR(8) NOT NULL,
  ubicacion VARCHAR(255), observaciones TEXT, estado ENUM('Programado','En_curso','Completado','Cancelado') NOT NULL DEFAULT 'Programado',
  recinto_id VARCHAR(30) NULL, recinto_nombre VARCHAR(150), created_by_id VARCHAR(30) NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY idx_turnos_guardia (guardia_id), KEY idx_turnos_recinto (recinto_id), KEY idx_turnos_estado (estado), KEY idx_turnos_fecha (fecha), KEY idx_turnos_created_by (created_by_id),
  CONSTRAINT fk_turnos_guardia FOREIGN KEY (guardia_id) REFERENCES guardias(id) ON DELETE SET NULL,
  CONSTRAINT fk_turnos_recinto FOREIGN KEY (recinto_id) REFERENCES recintos(id) ON DELETE SET NULL,
  CONSTRAINT fk_turnos_creator FOREIGN KEY (created_by_id) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE rondas (
  id VARCHAR(30) PRIMARY KEY, guardia_id VARCHAR(30) NULL, guardia_nombre VARCHAR(150) NOT NULL,
  fecha_hora_inicio DATETIME NOT NULL, fecha_hora_fin DATETIME NULL, puntos_recorridos TEXT, novedades TEXT,
  estado ENUM('Programada','En_curso','Completada','Incidente') NOT NULL DEFAULT 'Programada', ruta JSON NOT NULL,
  distancia_m DECIMAL(12,2) NOT NULL DEFAULT 0, recinto_id VARCHAR(30) NULL, recinto_nombre VARCHAR(150), created_by_id VARCHAR(30) NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY idx_rondas_guardia (guardia_id), KEY idx_rondas_recinto (recinto_id), KEY idx_rondas_estado (estado), KEY idx_rondas_inicio (fecha_hora_inicio), KEY idx_rondas_created_by (created_by_id),
  CONSTRAINT fk_rondas_guardia FOREIGN KEY (guardia_id) REFERENCES guardias(id) ON DELETE SET NULL,
  CONSTRAINT fk_rondas_recinto FOREIGN KEY (recinto_id) REFERENCES recintos(id) ON DELETE SET NULL,
  CONSTRAINT fk_rondas_creator FOREIGN KEY (created_by_id) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE entradas (
  id VARCHAR(30) PRIMARY KEY, visitante_nombre VARCHAR(150) NOT NULL, visitante_documento VARCHAR(80), vehiculo VARCHAR(80), motivo VARCHAR(255), persona_visita VARCHAR(150),
  hora_entrada DATETIME NOT NULL, hora_salida DATETIME NULL, guardia_id VARCHAR(30) NULL, guardia_nombre VARCHAR(150),
  estado ENUM('Dentro','Salio','Denegado') NOT NULL DEFAULT 'Dentro', recinto_id VARCHAR(30) NULL, recinto_nombre VARCHAR(150), created_by_id VARCHAR(30) NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY idx_entradas_guardia (guardia_id), KEY idx_entradas_recinto (recinto_id), KEY idx_entradas_estado (estado), KEY idx_entradas_hora (hora_entrada), KEY idx_entradas_created_by (created_by_id),
  CONSTRAINT fk_entradas_guardia FOREIGN KEY (guardia_id) REFERENCES guardias(id) ON DELETE SET NULL,
  CONSTRAINT fk_entradas_recinto FOREIGN KEY (recinto_id) REFERENCES recintos(id) ON DELETE SET NULL,
  CONSTRAINT fk_entradas_creator FOREIGN KEY (created_by_id) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE reportes (
  id VARCHAR(30) PRIMARY KEY, titulo VARCHAR(180) NOT NULL, tipo ENUM('Novedad','Incidencia','Siniestro','Mantenimiento','Otro') NOT NULL,
  severidad ENUM('Baja','Media','Alta','Critica') NOT NULL, fecha DATETIME NOT NULL, descripcion TEXT, ubicacion VARCHAR(255),
  guardia_id VARCHAR(30) NULL, guardia_nombre VARCHAR(150), estado ENUM('Abierto','En_revision','Resuelto','Cerrado') NOT NULL DEFAULT 'Abierto',
  recinto_id VARCHAR(30) NULL, recinto_nombre VARCHAR(150), created_by_id VARCHAR(30) NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY idx_reportes_guardia (guardia_id), KEY idx_reportes_recinto (recinto_id), KEY idx_reportes_estado (estado), KEY idx_reportes_fecha (fecha), KEY idx_reportes_created_by (created_by_id),
  CONSTRAINT fk_reportes_guardia FOREIGN KEY (guardia_id) REFERENCES guardias(id) ON DELETE SET NULL,
  CONSTRAINT fk_reportes_recinto FOREIGN KEY (recinto_id) REFERENCES recintos(id) ON DELETE SET NULL,
  CONSTRAINT fk_reportes_creator FOREIGN KEY (created_by_id) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE alertas (
  id VARCHAR(30) PRIMARY KEY, titulo VARCHAR(180) NOT NULL,
  tipo ENUM('Intrusion','Emergencia','Sistema','Acceso_no_autorizado','Otro') NOT NULL,
  nivel ENUM('Info','Advertencia','Critica') NOT NULL, fecha DATETIME NOT NULL, mensaje TEXT, ubicacion VARCHAR(255), guardia_id VARCHAR(30) NULL,
  estado ENUM('Activa','Atendida','Resuelta') NOT NULL DEFAULT 'Activa', recinto_id VARCHAR(30) NULL, recinto_nombre VARCHAR(150), created_by_id VARCHAR(30) NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY idx_alertas_guardia (guardia_id), KEY idx_alertas_recinto (recinto_id), KEY idx_alertas_estado (estado), KEY idx_alertas_fecha (fecha), KEY idx_alertas_created_by (created_by_id),
  CONSTRAINT fk_alertas_guardia FOREIGN KEY (guardia_id) REFERENCES guardias(id) ON DELETE SET NULL,
  CONSTRAINT fk_alertas_recinto FOREIGN KEY (recinto_id) REFERENCES recintos(id) ON DELETE SET NULL,
  CONSTRAINT fk_alertas_creator FOREIGN KEY (created_by_id) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE relevos (
  id VARCHAR(30) PRIMARY KEY, turno_id VARCHAR(30) NULL,
  guardia_saliente_id VARCHAR(30) NULL, guardia_saliente_nombre VARCHAR(150) NOT NULL,
  guardia_entrante_id VARCHAR(30) NULL, guardia_entrante_nombre VARCHAR(150) NOT NULL,
  recinto_id VARCHAR(30) NULL, recinto_nombre VARCHAR(150) NULL,
  fecha_hora DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, novedades TEXT NOT NULL,
  estado_entrega VARCHAR(30) NOT NULL DEFAULT 'Completa', created_by_id VARCHAR(30) NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY idx_relevos_fecha (fecha_hora), KEY idx_relevos_saliente (guardia_saliente_id), KEY idx_relevos_entrante (guardia_entrante_id),
  CONSTRAINT fk_relevos_creator FOREIGN KEY (created_by_id) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE configuracion (
  id TINYINT UNSIGNED PRIMARY KEY DEFAULT 1, permitir_registro_publico BOOLEAN NOT NULL DEFAULT FALSE,
  smtp_host VARCHAR(190) NULL, smtp_port SMALLINT UNSIGNED NOT NULL DEFAULT 587,
  smtp_secure BOOLEAN NOT NULL DEFAULT FALSE, smtp_user VARCHAR(190) NULL, smtp_password VARCHAR(255) NULL,
  mail_from VARCHAR(255) NULL, telegram_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  telegram_bot_token VARCHAR(255) NULL, telegram_chat_id VARCHAR(100) NULL,
  alert_email_enabled BOOLEAN NOT NULL DEFAULT FALSE, alert_telegram_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  report_email_enabled BOOLEAN NOT NULL DEFAULT FALSE, report_telegram_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  notification_email VARCHAR(190) NULL,
  shift_email_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  timezone VARCHAR(80) NOT NULL DEFAULT 'America/Santiago', date_format VARCHAR(20) NOT NULL DEFAULT 'DD/MM/YYYY', time_format VARCHAR(10) NOT NULL DEFAULT '24h',
  turno_dia_inicio VARCHAR(8) NOT NULL DEFAULT '08:00', turno_dia_fin VARCHAR(8) NOT NULL DEFAULT '20:00',
  turno_noche_inicio VARCHAR(8) NOT NULL DEFAULT '20:00', turno_noche_fin VARCHAR(8) NOT NULL DEFAULT '08:00',
  theme VARCHAR(30) NOT NULL DEFAULT 'esmeralda', brand_name VARCHAR(100) NOT NULL DEFAULT 'GuardiaPro',
  brand_subtitle VARCHAR(150) NOT NULL DEFAULT 'Centro de operaciones',
  hero_title VARCHAR(255) NOT NULL DEFAULT 'Seguridad conectada, decisiones claras.', hero_description TEXT,
  hero_footer VARCHAR(255) NOT NULL DEFAULT 'Protección visible. Gestión inteligente.',
  logo_url MEDIUMTEXT NULL, icon_url MEDIUMTEXT NULL, hero_image_url MEDIUMTEXT NULL,
  public_page_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  public_banner_color VARCHAR(20) NOT NULL DEFAULT '#e2e8f0',
  company_contact_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  company_contact_name VARCHAR(150) NULL, company_email VARCHAR(190) NULL,
  company_phone VARCHAR(40) NULL, company_address VARCHAR(255) NULL, company_website_url VARCHAR(500) NULL,
  company_title VARCHAR(255) NOT NULL DEFAULT 'Seguridad que inspira confianza', company_description TEXT NULL,
  company_services TEXT NULL, quote_email VARCHAR(190) NULL,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT chk_config_singleton CHECK (id = 1)
) ENGINE=InnoDB;

CREATE TABLE otp_tokens (
  id VARCHAR(30) PRIMARY KEY, email VARCHAR(190) NOT NULL, code VARCHAR(255) NOT NULL, purpose VARCHAR(30) NOT NULL,
  expires_at DATETIME NOT NULL, created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY idx_otp_email_purpose (email, purpose), KEY idx_otp_expires (expires_at)
) ENGINE=InnoDB;
