ALTER TABLE users
  ADD COLUMN failed_login_attempts INT NOT NULL DEFAULT 0 AFTER enabled,
  ADD COLUMN locked_until DATETIME NULL AFTER failed_login_attempts,
  ADD COLUMN last_login_at DATETIME NULL AFTER locked_until;

CREATE TABLE IF NOT EXISTS sessions (
  id VARCHAR(30) PRIMARY KEY,user_id VARCHAR(30) NOT NULL,expires_at DATETIME NOT NULL,revoked_at DATETIME NULL,
  ip_address VARCHAR(191) NULL,user_agent TEXT NULL,created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY idx_sessions_user_revoked (user_id,revoked_at),KEY idx_sessions_expires (expires_at),
  CONSTRAINT fk_sessions_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS audit_logs (
  id VARCHAR(30) PRIMARY KEY,user_id VARCHAR(30) NULL,action VARCHAR(191) NOT NULL,entity VARCHAR(191) NULL,entity_id VARCHAR(30) NULL,
  detail JSON NULL,ip_address VARCHAR(191) NULL,user_agent TEXT NULL,created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY idx_audit_user_created (user_id,created_at),KEY idx_audit_action_created (action,created_at),
  CONSTRAINT fk_audit_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB;
