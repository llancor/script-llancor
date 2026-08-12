USE seguridad_rrhh;
SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;
ALTER TABLE configuracion
  ADD COLUMN theme VARCHAR(30) NOT NULL DEFAULT 'esmeralda',
  ADD COLUMN brand_name VARCHAR(100) NOT NULL DEFAULT 'Seguridad',
  ADD COLUMN brand_subtitle VARCHAR(150) NOT NULL DEFAULT 'Centro de operaciones',
  ADD COLUMN hero_title VARCHAR(255) NOT NULL DEFAULT 'Seguridad conectada, decisiones claras.',
  ADD COLUMN hero_description TEXT NULL,
  ADD COLUMN hero_footer VARCHAR(255) NOT NULL DEFAULT 'Protección visible. Gestión inteligente.',
  ADD COLUMN logo_url MEDIUMTEXT NULL,
  ADD COLUMN icon_url MEDIUMTEXT NULL,
  ADD COLUMN hero_image_url MEDIUMTEXT NULL,
  ADD COLUMN public_page_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN company_title VARCHAR(255) NOT NULL DEFAULT 'Seguridad que inspira confianza',
  ADD COLUMN company_description TEXT NULL,
  ADD COLUMN company_services TEXT NULL,
  ADD COLUMN quote_email VARCHAR(190) NULL;
