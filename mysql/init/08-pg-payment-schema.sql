-- EroomPay MSA MySQL DDL
-- Target: MySQL 8.0+
SET NAMES utf8mb4;
SET time_zone = '+09:00';

CREATE DATABASE IF NOT EXISTS pg_payment_db DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
-- =========================================================
-- pg_payment_db
-- =========================================================
USE pg_payment_db;

CREATE TABLE IF NOT EXISTS pg_payment_ledger (
  pg_txn_id BIGINT NOT NULL AUTO_INCREMENT,
  original_txn_id BIGINT NULL COMMENT 'VOID/CANCEL 대상 원거래, 자기참조',
  pay_payment_id BIGINT NOT NULL COMMENT 'payment_db.payment_orders.payment_id 논리 참조',
  hold_txn_id BIGINT NULL COMMENT '더치페이 대표자 AUTH_ONLY pg_txn_id 자기참조',
  idempotency_key VARCHAR(64) NOT NULL,
  billing_key VARCHAR(100) NOT NULL COMMENT 'billing-key-service 발급 빌링키, 로그/응답 노출 금지',
  merchant_id BIGINT NOT NULL COMMENT 'pg_merchant_db.pg_merchants.merchant_id 논리 참조',
  amount BIGINT NOT NULL,
  txn_type ENUM('AUTH','AUTH_ONLY','VOID','CANCEL') NOT NULL,
  status ENUM('REQUESTED','APPROVED','REJECTED','FAILED','CANCELLED','VOIDED') NOT NULL DEFAULT 'REQUESTED',
  pg_approval_number VARCHAR(50) NULL,
  card_company VARCHAR(50) NOT NULL,
  card_approval_number VARCHAR(50) NULL,
  reject_reason VARCHAR(200) NULL,
  failure_code VARCHAR(50) NULL,
  failure_message VARCHAR(255) NULL,
  retry_count TINYINT NOT NULL DEFAULT 0,
  approved_at DATETIME NULL,
  processed_at DATETIME NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (pg_txn_id),
  UNIQUE KEY uk_pg_payment_ledger_idempotency (idempotency_key),
  KEY idx_pg_payment_ledger_original (original_txn_id),
  KEY idx_pg_payment_ledger_hold (hold_txn_id),
  KEY idx_pg_payment_ledger_merchant_created (merchant_id, created_at),
  KEY idx_pg_payment_ledger_status (status),
  CONSTRAINT fk_pg_payment_ledger_original FOREIGN KEY (original_txn_id) REFERENCES pg_payment_ledger(pg_txn_id),
  CONSTRAINT fk_pg_payment_ledger_hold FOREIGN KEY (hold_txn_id) REFERENCES pg_payment_ledger(pg_txn_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
