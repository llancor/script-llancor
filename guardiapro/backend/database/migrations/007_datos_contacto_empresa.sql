USE guardiapro;
SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;
ALTER TABLE configuracion
  ADD COLUMN company_contact_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN company_contact_name VARCHAR(150) NULL,
  ADD COLUMN company_email VARCHAR(190) NULL,
  ADD COLUMN company_phone VARCHAR(40) NULL,
  ADD COLUMN company_address VARCHAR(255) NULL,
  ADD COLUMN company_website_url VARCHAR(500) NULL;
