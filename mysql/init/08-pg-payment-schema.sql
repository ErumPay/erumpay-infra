-- EroomPay MSA MySQL DDL
-- Target: MySQL 8.0+
SET NAMES utf8mb4;
SET time_zone = '+09:00';

CREATE DATABASE IF NOT EXISTS pg_payment_db DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

-- =========================================================
-- pg_payment_db
-- =========================================================
USE pg_payment_db;

CREATE TABLE IF NOT EXISTS pg_payment_group (
  pg_group_id BIGINT NOT NULL AUTO_INCREMENT,
  pay_payment_id BIGINT NOT NULL COMMENT 'Logical reference to payment-service payment id',
  merchant_id BIGINT NOT NULL COMMENT 'Logical reference to merchant id',
  idempotency_key VARCHAR(64) NOT NULL,
  total_amount BIGINT NOT NULL,
  status ENUM(
    'REQUESTED',
    'HOLDING',
    'HELD',
    'CAPTURING',
    'APPROVED',
    'REJECTED',
    'FAILED',
    'VOIDING',
    'CANCELLING',
    'CANCELLED',
    'RECOVERY_REQUIRED',
    'COMPENSATION_REQUIRED'
  ) NOT NULL DEFAULT 'REQUESTED',
  failure_code VARCHAR(50) NULL,
  failure_message VARCHAR(255) NULL,
  retry_count INT NOT NULL DEFAULT 0,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (pg_group_id),
  UNIQUE KEY uk_pg_payment_group_idempotency (idempotency_key),
  KEY idx_pg_payment_group_pay_payment (pay_payment_id),
  KEY idx_pg_payment_group_merchant_created (merchant_id, created_at),
  KEY idx_pg_payment_group_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS pg_payment_ledger (
  pg_txn_id BIGINT NOT NULL AUTO_INCREMENT,
  pg_group_id BIGINT NULL COMMENT 'Split payment group id',
  split_seq INT NULL COMMENT 'Split payment item sequence in group',
  original_txn_id BIGINT NULL COMMENT 'Original PG transaction id for VOID/CANCEL/CAPTURE',
  pay_payment_id BIGINT NOT NULL COMMENT 'Logical reference to payment-service payment id',
  hold_txn_id BIGINT NULL COMMENT 'AUTH_ONLY hold transaction id for linked payment flows',
  idempotency_key VARCHAR(64) NOT NULL,
  billing_key VARCHAR(100) NOT NULL COMMENT 'Billing key from billing-key-service',
  merchant_id BIGINT NOT NULL COMMENT 'Logical reference to merchant id',
  amount BIGINT NOT NULL,
  txn_type ENUM('AUTH','AUTH_ONLY','CAPTURE','VOID','CANCEL') NOT NULL,
  status ENUM(
    'REQUESTED',
    'HELD',
    'APPROVED',
    'CAPTURED',
    'REJECTED',
    'FAILED',
    'CANCELLED',
    'VOIDED',
    'RECOVERY_REQUIRED',
    'COMPENSATION_REQUIRED'
  ) NOT NULL DEFAULT 'REQUESTED',
  pg_approval_number VARCHAR(50) NULL,
  card_company VARCHAR(50) NOT NULL,
  card_approval_number VARCHAR(50) NULL,
  reject_reason VARCHAR(200) NULL,
  failure_code VARCHAR(50) NULL,
  failure_message VARCHAR(255) NULL,
  retry_count INT NOT NULL DEFAULT 0,
  approved_at DATETIME NULL,
  processed_at DATETIME NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (pg_txn_id),
  UNIQUE KEY uk_pg_payment_ledger_idempotency (idempotency_key),
  KEY idx_pg_payment_ledger_pay_payment (pay_payment_id),
  KEY idx_pg_payment_ledger_group (pg_group_id),
  KEY idx_pg_payment_ledger_group_split (pg_group_id, split_seq),
  KEY idx_pg_payment_ledger_original (original_txn_id),
  KEY idx_pg_payment_ledger_hold (hold_txn_id),
  KEY idx_pg_payment_ledger_merchant_created (merchant_id, created_at),
  KEY idx_pg_payment_ledger_status (status),
  CONSTRAINT fk_pg_payment_ledger_group FOREIGN KEY (pg_group_id) REFERENCES pg_payment_group(pg_group_id),
  CONSTRAINT fk_pg_payment_ledger_original FOREIGN KEY (original_txn_id) REFERENCES pg_payment_ledger(pg_txn_id),
  CONSTRAINT fk_pg_payment_ledger_hold FOREIGN KEY (hold_txn_id) REFERENCES pg_payment_ledger(pg_txn_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
