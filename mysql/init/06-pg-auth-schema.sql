-- EroomPay MSA MySQL DDL
-- Target: MySQL 8.0+
SET NAMES utf8mb4;
SET time_zone = '+09:00';

CREATE DATABASE IF NOT EXISTS pg_auth_db DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
-- =========================================================
-- pg_auth_db
-- =========================================================
USE pg_auth_db;

CREATE TABLE IF NOT EXISTS pg_merchant_accounts (
  account_id BIGINT NOT NULL AUTO_INCREMENT,
  merchant_id BIGINT NOT NULL COMMENT 'pg_merchant_db.pg_merchants.merchant_id 논리 참조',
  kakao_oauth_id VARCHAR(100) NOT NULL,
  name VARCHAR(50) NOT NULL,
  role ENUM('OWNER','STAFF') NOT NULL,
  status ENUM('DRAFT','PENDING','ACTIVE','REJECTED','SUSPENDED','WITHDRAWN') NOT NULL DEFAULT 'DRAFT',
  last_login_at DATETIME NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at DATETIME NULL,
  PRIMARY KEY (account_id),
  UNIQUE KEY uk_pg_merchant_accounts_kakao_oauth_id (kakao_oauth_id),
  KEY idx_pg_merchant_accounts_merchant (merchant_id),
  KEY idx_pg_merchant_accounts_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS pg_merchant_terms_agreements (
  agreement_id BIGINT NOT NULL AUTO_INCREMENT,
  account_id BIGINT NOT NULL,
  service_terms_agreed BOOLEAN NOT NULL,
  privacy_policy_agreed BOOLEAN NOT NULL,
  marketing_agreed BOOLEAN NOT NULL DEFAULT FALSE,
  terms_version VARCHAR(20) NOT NULL,
  agreed_ip VARCHAR(50) NULL,
  agreed_at DATETIME NULL,
  PRIMARY KEY (agreement_id),
  KEY idx_pg_merchant_terms_account (account_id),
  CONSTRAINT fk_pg_merchant_terms_account FOREIGN KEY (account_id) REFERENCES pg_merchant_accounts(account_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS pg_merchant_refresh_tokens (
  token_id BIGINT NOT NULL AUTO_INCREMENT,
  account_id BIGINT NOT NULL,
  token_hash VARCHAR(255) NOT NULL,
  expires_at DATETIME NOT NULL,
  is_revoked BOOLEAN NOT NULL DEFAULT FALSE,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (token_id),
  UNIQUE KEY uk_pg_merchant_refresh_tokens_hash (token_hash),
  KEY idx_pg_merchant_refresh_tokens_account (account_id),
  CONSTRAINT fk_pg_merchant_refresh_tokens_account FOREIGN KEY (account_id) REFERENCES pg_merchant_accounts(account_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS pg_admin_accounts (
  admin_id BIGINT NOT NULL AUTO_INCREMENT,
  login_id VARCHAR(50) NOT NULL,
  password_hash VARCHAR(255) NOT NULL COMMENT 'bcrypt',
  totp_secret VARCHAR(255) NULL COMMENT 'AES-256 암호화, 2FA용',
  allowed_ips TEXT NULL,
  last_login_at DATETIME NULL,
  locked_until DATETIME NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  failed_login_count INT NOT NULL DEFAULT 0,
  PRIMARY KEY (admin_id),
  UNIQUE KEY uk_pg_admin_accounts_login_id (login_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS pg_admin_audit_logs (
  log_id BIGINT NOT NULL AUTO_INCREMENT,
  admin_id BIGINT NOT NULL,
  action VARCHAR(100) NOT NULL,
  target_id VARCHAR(100) NULL,
  change_detail TEXT NULL COMMENT 'JSON 형태 권장',
  ip_address VARCHAR(50) NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (log_id),
  KEY idx_pg_admin_audit_logs_admin (admin_id),
  KEY idx_pg_admin_audit_logs_created (created_at),
  CONSTRAINT fk_pg_admin_audit_logs_admin FOREIGN KEY (admin_id) REFERENCES pg_admin_accounts(admin_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS pg_admin_refresh_tokens (
  token_id BIGINT NOT NULL AUTO_INCREMENT,
  admin_id BIGINT NOT NULL,
  token_hash VARCHAR(255) NOT NULL,
  expires_at DATETIME NOT NULL,
  is_revoked BOOLEAN NOT NULL DEFAULT FALSE,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (token_id),
  UNIQUE KEY uk_pg_admin_refresh_tokens_hash (token_hash),
  KEY idx_pg_admin_refresh_tokens_admin (admin_id),
  CONSTRAINT fk_pg_admin_refresh_tokens_admin FOREIGN KEY (admin_id) REFERENCES pg_admin_accounts(admin_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
