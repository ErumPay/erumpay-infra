-- EroomPay MSA MySQL DDL
-- Target: MySQL 8.0+
SET NAMES utf8mb4;
SET time_zone = '+09:00';

CREATE DATABASE IF NOT EXISTS simulator_db DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
-- =========================================================
-- simulator_db (card-simulator-service)
-- =========================================================
USE simulator_db;

CREATE TABLE IF NOT EXISTS simulator_user (
  user_id BIGINT NOT NULL AUTO_INCREMENT,
  name VARCHAR(50) NOT NULL,
  phone_number VARCHAR(255) NOT NULL COMMENT 'AES-256 암호화 저장',
  birth_date VARCHAR(255) NOT NULL COMMENT 'YYMMDD AES-256 암호화 저장',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id),
  UNIQUE KEY uk_simulator_user_name_phone (name, phone_number)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS simulator_card_product (
  product_id BIGINT NOT NULL AUTO_INCREMENT,
  card_company VARCHAR(50) NOT NULL,
  product_name VARCHAR(100) NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (product_id),
  UNIQUE KEY uk_simulator_card_product_company_name (card_company, product_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS simulator_card (
  card_id BIGINT NOT NULL AUTO_INCREMENT,
  user_id BIGINT NOT NULL,
  product_id BIGINT NOT NULL,
  card_company VARCHAR(50) NOT NULL,
  card_number VARCHAR(255) NOT NULL COMMENT 'AES-256 암호화 저장',
  masked_number VARCHAR(25) NOT NULL,
  expiry_date VARCHAR(4) NOT NULL COMMENT 'YYMM',
  cvc VARCHAR(255) NOT NULL COMMENT 'AES-256 암호화 저장',
  password VARCHAR(255) NOT NULL COMMENT 'AES-256 암호화 저장',
  password_2digit VARCHAR(255) NOT NULL COMMENT 'SHA-256 + SALT 해싱',
  birth_date VARCHAR(255) NOT NULL COMMENT 'YYMMDD AES-256 암호화 저장',
  card_status ENUM('ACTIVE','LOST','EXPIRE','DELETE') NOT NULL DEFAULT 'ACTIVE',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (card_id),
  UNIQUE KEY uk_simulator_card_company_number (card_company, card_number),
  KEY idx_simulator_card_user (user_id),
  KEY idx_simulator_card_product (product_id),
  KEY idx_simulator_card_status (card_status),
  CONSTRAINT fk_simulator_card_user FOREIGN KEY (user_id) REFERENCES simulator_user(user_id),
  CONSTRAINT fk_simulator_card_product FOREIGN KEY (product_id) REFERENCES simulator_card_product(product_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS simulator_card_token (
  token_id BIGINT NOT NULL AUTO_INCREMENT,
  card_token VARCHAR(200) NOT NULL COMMENT 'AES-256 암호화 저장',
  card_id BIGINT NOT NULL,
  card_company VARCHAR(50) NOT NULL,
  pg_id VARCHAR(20) NOT NULL,
  request_id_create VARCHAR(50) NOT NULL COMMENT '발급 멱등성 보장',
  request_id_delete VARCHAR(50) NULL COMMENT '삭제 멱등성 보장',
  token_status ENUM('ACTIVE','DELETE') NOT NULL DEFAULT 'ACTIVE',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (token_id),
  UNIQUE KEY uk_simulator_card_token_token (card_token),
  UNIQUE KEY uk_simulator_card_token_create_req (request_id_create),
  UNIQUE KEY uk_simulator_card_token_delete_req (request_id_delete),
  UNIQUE KEY uk_simulator_card_token_card_pg (card_id, pg_id),
  KEY idx_simulator_card_token_card (card_id),
  CONSTRAINT fk_simulator_card_token_card FOREIGN KEY (card_id) REFERENCES simulator_card(card_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS simulator_pre_approval (
  pre_approval_id BIGINT NOT NULL AUTO_INCREMENT,
  card_id BIGINT NOT NULL,
  card_company VARCHAR(50) NOT NULL,
  pg_id VARCHAR(20) NOT NULL,
  pg_txn_id BIGINT NOT NULL COMMENT 'pg_payment_ledger.pg_txn_id 논리 참조',
  origin_pg_txn_id BIGINT NULL,
  idempotency_key VARCHAR(64) NOT NULL,
  original_amount BIGINT NOT NULL,
  approved_amount BIGINT NOT NULL,
  pre_approval_number VARCHAR(50) NOT NULL,
  pre_approval_status ENUM('PENDING','CANCEL','EXPIRE') NOT NULL DEFAULT 'PENDING',
  response_code INT NOT NULL,
  response_message VARCHAR(200) NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (pre_approval_id),
  UNIQUE KEY uk_simulator_pre_approval_pg_txn (pg_txn_id),
  UNIQUE KEY uk_simulator_pre_approval_idempotency (idempotency_key),
  KEY idx_simulator_pre_approval_card (card_id),
  KEY idx_simulator_pre_approval_status (pre_approval_status),
  CONSTRAINT fk_simulator_pre_approval_card FOREIGN KEY (card_id) REFERENCES simulator_card(card_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS simulator_payment_history (
  payment_id BIGINT NOT NULL AUTO_INCREMENT,
  card_id BIGINT NOT NULL,
  pg_txn_id BIGINT NOT NULL COMMENT 'pg_payment_ledger.pg_txn_id 논리 참조',
  idempotency_key VARCHAR(64) NOT NULL,
  pg_id VARCHAR(20) NOT NULL,
  card_company VARCHAR(50) NOT NULL,
  origin_pg_txn_id BIGINT NULL,
  payment_status ENUM('APPROVAL','CANCEL') NOT NULL DEFAULT 'APPROVAL',
  original_amount BIGINT NOT NULL,
  approved_amount BIGINT NOT NULL,
  performance_date DATETIME NOT NULL,
  approval_number VARCHAR(50) NOT NULL,
  response_code INT NOT NULL,
  response_message VARCHAR(200) NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (payment_id),
  UNIQUE KEY uk_simulator_payment_history_pg_txn (pg_txn_id),
  UNIQUE KEY uk_simulator_payment_history_idempotency (idempotency_key),
  KEY idx_simulator_payment_history_card (card_id),
  KEY idx_simulator_payment_history_perf_date (performance_date),
  CONSTRAINT fk_simulator_payment_history_card FOREIGN KEY (card_id) REFERENCES simulator_card(card_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS simulator_response_code (
  code_id BIGINT NOT NULL AUTO_INCREMENT,
  card_company VARCHAR(50) NOT NULL,
  response_code INT NOT NULL,
  response_message VARCHAR(200) NOT NULL,
  response_type ENUM('NORMAL','EXPIRED','LOST','DELETED','FAILED') NOT NULL DEFAULT 'NORMAL',
  PRIMARY KEY (code_id),
  UNIQUE KEY uk_simulator_response_code_company_code (card_company, response_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS simulator_config (
  config_id BIGINT NOT NULL AUTO_INCREMENT,
  approval_rate DECIMAL(5,2) NOT NULL DEFAULT 98.00 COMMENT '단위: %',
  delay_ms INT NOT NULL DEFAULT 0 COMMENT '단위: ms',
  reject_pattern VARCHAR(200) NULL COMMENT '정규식 패턴 예: 9999$',
  PRIMARY KEY (config_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
