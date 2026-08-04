USE guardiapro;
SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;
ALTER TABLE configuracion ADD COLUMN public_banner_color VARCHAR(20) NOT NULL DEFAULT '#e2e8f0';
