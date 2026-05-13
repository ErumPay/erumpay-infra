-- EroomPay MSA MySQL DDL
-- Target: MySQL 8.0+
SET NAMES utf8mb4;
SET time_zone = '+09:00';

CREATE DATABASE IF NOT EXISTS pg_merchant_db DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
-- =========================================================
-- pg_merchant_db
-- =========================================================
USE pg_merchant_db;

CREATE TABLE IF NOT EXISTS pg_merchants (
  merchant_id BIGINT NOT NULL AUTO_INCREMENT,
  merchant_name VARCHAR(100) NOT NULL,
  business_number VARCHAR(20) NOT NULL,
  owner_name VARCHAR(50) NOT NULL,
  contact_phone VARCHAR(20) NOT NULL,
  business_address VARCHAR(255) NOT NULL,
  category_name VARCHAR(50) NOT NULL,
  mcc_code CHAR(4) NOT NULL COMMENT 'ISO 18245',
  api_key VARCHAR(255) NOT NULL COMMENT 'AES-256 암호화, 온라인 연동용',
  api_key_status ENUM('ACTIVE','SUSPENDED','REVOKED') NOT NULL DEFAULT 'ACTIVE',
  api_key_issued_at DATETIME NOT NULL,
  api_key_rotated_at DATETIME NULL,
  fee_rate DECIMAL(5,2) NOT NULL DEFAULT 1.50,
  settlement_account VARCHAR(100) NOT NULL COMMENT 'AES-256 암호화',
  status ENUM('DRAFT','PENDING','ACTIVE','REJECTED','SUSPENDED','WITHDRAWN') NOT NULL DEFAULT 'DRAFT',
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  suspend_reason VARCHAR(200) NULL,
  deleted_at DATETIME NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (merchant_id),
  UNIQUE KEY uk_pg_merchants_business_number (business_number),
  UNIQUE KEY uk_pg_merchants_api_key (api_key),
  KEY idx_pg_merchants_status (status),
  KEY idx_pg_merchants_mcc (mcc_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS pg_settlements (
  settlement_id BIGINT NOT NULL AUTO_INCREMENT,
  merchant_id BIGINT NOT NULL,
  period_type ENUM('DAILY','MONTHLY') NOT NULL,
  period_start DATE NOT NULL,
  period_end DATE NOT NULL,
  total_sales BIGINT NOT NULL DEFAULT 0,
  cancel_amount BIGINT NOT NULL DEFAULT 0,
  net_sales BIGINT NOT NULL DEFAULT 0,
  settlement_amount BIGINT NOT NULL DEFAULT 0,
  fee_amount BIGINT NOT NULL DEFAULT 0,
  fee_rate DECIMAL(5,2) NOT NULL,
  payment_count BIGINT NOT NULL DEFAULT 0,
  cancel_count BIGINT NOT NULL DEFAULT 0,
  status ENUM('PENDING','COMPLETED','FAILED') NOT NULL DEFAULT 'PENDING',
  settled_at DATETIME NULL,
  expected_payment_date DATE NULL,
  fail_reason VARCHAR(200) NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (settlement_id),
  UNIQUE KEY uk_pg_settlements_merchant_period (merchant_id, period_type, period_start),
  KEY idx_pg_settlements_status (status),
  CONSTRAINT fk_pg_settlements_merchant FOREIGN KEY (merchant_id) REFERENCES pg_merchants(merchant_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS pg_merchant_status_history (
  history_id BIGINT NOT NULL AUTO_INCREMENT,
  merchant_id BIGINT NOT NULL,
  from_status ENUM('DRAFT','PENDING','ACTIVE','REJECTED','SUSPENDED','WITHDRAWN') NULL,
  to_status ENUM('DRAFT','PENDING','ACTIVE','REJECTED','SUSPENDED','WITHDRAWN') NOT NULL,
  reason VARCHAR(200) NULL,
  changed_by BIGINT NULL COMMENT 'pg_admin_accounts.admin_id 또는 SYSTEM(0), 논리 참조',
  changed_at DATETIME NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (history_id),
  KEY idx_pg_merchant_status_history_merchant (merchant_id, changed_at),
  CONSTRAINT fk_pg_merchant_status_history_merchant FOREIGN KEY (merchant_id) REFERENCES pg_merchants(merchant_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS pg_merchant_audit_log (
  audit_id BIGINT NOT NULL AUTO_INCREMENT,
  admin_id BIGINT NOT NULL COMMENT 'pg_auth_db.pg_admin_accounts.admin_id 논리 참조',
  merchant_id BIGINT NOT NULL,
  action_type ENUM('MERCHANT_STATUS_CHANGED','SETTLEMENT_UPDATED','MERCHANT_SUSPENDED','API_KEY_ROTATED','FEE_RATE_UPDATED') NOT NULL,
  action_detail VARCHAR(255) NULL,
  ip_address VARCHAR(50) NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (audit_id),
  KEY idx_pg_merchant_audit_log_admin (admin_id),
  KEY idx_pg_merchant_audit_log_merchant (merchant_id),
  KEY idx_pg_merchant_audit_log_created (created_at),
  CONSTRAINT fk_pg_merchant_audit_log_merchant FOREIGN KEY (merchant_id) REFERENCES pg_merchants(merchant_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
