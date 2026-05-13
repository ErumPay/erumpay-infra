-- EroomPay MSA MySQL DDL
-- Target: MySQL 8.0+
SET NAMES utf8mb4;
SET time_zone = '+09:00';

CREATE DATABASE IF NOT EXISTS pg_billing_db DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
-- =========================================================
-- pg_billing_db (billing-key-service)
-- =========================================================
USE pg_billing_db;

CREATE TABLE IF NOT EXISTS pg_billing_keys (
  billing_key_id BIGINT NOT NULL AUTO_INCREMENT,
  billing_key VARCHAR(40) NOT NULL COMMENT 'UUID 기반 랜덤 토큰',
  pay_card_id BIGINT NOT NULL COMMENT 'card_db.card_registered.card_id 논리 참조',
  card_token VARCHAR(200) NOT NULL COMMENT '카드사 발급 토큰, AES-256 암호화 권장',
  masked_number VARCHAR(25) NOT NULL,
  card_company VARCHAR(50) NOT NULL,
  status ENUM('ACTIVE','DELETE') NOT NULL DEFAULT 'ACTIVE',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (billing_key_id),
  UNIQUE KEY uk_pg_billing_keys_billing_key (billing_key),
  UNIQUE KEY uk_pg_billing_keys_pay_card_id (pay_card_id),
  KEY idx_pg_billing_keys_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
