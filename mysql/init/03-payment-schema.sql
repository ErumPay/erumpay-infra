-- EroomPay MSA MySQL DDL
-- Target: MySQL 8.0+
SET NAMES utf8mb4;
SET time_zone = '+09:00';

CREATE DATABASE IF NOT EXISTS payment_db DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
-- =========================================================
-- payment_db (payment-service)
-- =========================================================
USE payment_db;

CREATE TABLE IF NOT EXISTS payment_orders (
  payment_id BIGINT NOT NULL AUTO_INCREMENT,
  order_no VARCHAR(64) NOT NULL,
  order_name VARCHAR(100) NOT NULL,
  amount BIGINT NOT NULL,
  payment_status ENUM('CREATED','PAY_PENDING','PG_PENDING','PAID','FAILED','EXPIRED','AUTHORIZED','VOIDED','CANCELED') NOT NULL DEFAULT 'CREATED',
  idempotency_key VARCHAR(64) NULL,
  user_id BIGINT NULL COMMENT 'auth_users 논리 참조',
  merchant_id BIGINT NULL COMMENT 'pg_merchants 논리 참조',
  merchant_name VARCHAR(100) NULL,
  business_number VARCHAR(20) NULL,
  owner_name VARCHAR(50) NULL,
  contact_phone VARCHAR(20) NULL,
  business_address VARCHAR(255) NULL,
  channel_type ENUM('ONLINE','OFFLINE') NOT NULL,
  payment_type ENUM('SINGLE','DUTCH','REMOTE') NULL,
  dutch_session_id BIGINT NULL,
  dutch_role ENUM('HOST','MEMBER') NULL,
  remote_request_id BIGINT NULL,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  fail_code ENUM('CARD_EXPIRED','INVALID_PIN','QR_EXPIRED','NETWORK_ERROR','DUPLICATE_PAYMENT') NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  paid_at DATETIME NULL,
  canceled_at DATETIME NULL,
  PRIMARY KEY (payment_id),
  UNIQUE KEY uk_payment_orders_order_no (order_no),
  UNIQUE KEY uk_payment_orders_idempotency_key (idempotency_key),
  KEY idx_payment_orders_user_created (user_id, created_at),
  KEY idx_payment_orders_merchant (merchant_id),
  KEY idx_payment_orders_status (payment_status),
  KEY idx_payment_orders_dutch_session (dutch_session_id),
  KEY idx_payment_orders_remote_request (remote_request_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS payment_events (
  event_id BIGINT NOT NULL AUTO_INCREMENT,
  payment_id BIGINT NOT NULL,
  pg_txn_id BIGINT NULL COMMENT 'pg_payment_ledger 논리 참조',
  event_type ENUM('CREATED','PAY_PENDING','PG_PENDING','PAID','CANCEL_REQUESTED','CANCELED','FAILED','EXPIRED') NOT NULL,
  fail_code VARCHAR(50) NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  actor_type ENUM('USER','SYSTEM','PG','ADMIN') NOT NULL,
  PRIMARY KEY (event_id),
  KEY idx_payment_events_payment (payment_id, created_at),
  KEY idx_payment_events_type (event_type),
  CONSTRAINT fk_payment_events_payment FOREIGN KEY (payment_id) REFERENCES payment_orders(payment_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='append-only';

CREATE TABLE IF NOT EXISTS payment_qr (
  qr_id BIGINT NOT NULL AUTO_INCREMENT,
  payment_id BIGINT NOT NULL,
  token_hash VARCHAR(255) NOT NULL,
  is_used BOOLEAN NOT NULL DEFAULT FALSE,
  active INT GENERATED ALWAYS AS (CASE WHEN is_used = FALSE THEN 1 ELSE NULL END) STORED,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expired_at DATETIME NOT NULL,
  PRIMARY KEY (qr_id),
  UNIQUE KEY uk_payment_qr_token_hash (token_hash),
  UNIQUE KEY uk_payment_qr_payment_active (payment_id, active),
  KEY idx_payment_qr_payment (payment_id),
  KEY idx_payment_qr_expired (expired_at),
  CONSTRAINT fk_payment_qr_payment FOREIGN KEY (payment_id) REFERENCES payment_orders(payment_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS payment_card_details (
  payment_card_id BIGINT NOT NULL AUTO_INCREMENT,
  payment_id BIGINT NOT NULL,
  pg_txn_id BIGINT NOT NULL COMMENT 'pg_payment_ledger 논리 참조',
  pg_approval_num VARCHAR(50) NOT NULL,
  card_id BIGINT NOT NULL COMMENT 'card_registered 논리 참조',
  masked_number VARCHAR(25) NOT NULL,
  card_name VARCHAR(100) NOT NULL,
  paid_amount BIGINT NOT NULL,
  discount_amount BIGINT NOT NULL DEFAULT 0,
  benefit_desc VARCHAR(200) NULL,
  paid_at DATETIME NOT NULL,
  PRIMARY KEY (payment_card_id),
  KEY idx_payment_card_details_payment (payment_id),
  KEY idx_payment_card_details_pg_txn (pg_txn_id),
  KEY idx_payment_card_details_card (card_id),
  CONSTRAINT fk_payment_card_details_payment FOREIGN KEY (payment_id) REFERENCES payment_orders(payment_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS payment_cancel_history (
  cancel_id BIGINT NOT NULL AUTO_INCREMENT,
  payment_id BIGINT NOT NULL,
  amount BIGINT NULL,
  pg_txn_id BIGINT NULL COMMENT 'pg_payment_ledger 논리 참조',
  pg_cancel_approval_num VARCHAR(50) NULL,
  fail_code VARCHAR(50) NULL,
  cancel_status ENUM('REQUESTED','PG_PENDING','CANCELLED','FAILED') NOT NULL DEFAULT 'REQUESTED',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  canceled_at DATETIME NULL,
  PRIMARY KEY (cancel_id),
  KEY idx_payment_cancel_history_payment (payment_id),
  KEY idx_payment_cancel_history_status (cancel_status),
  CONSTRAINT fk_payment_cancel_history_payment FOREIGN KEY (payment_id) REFERENCES payment_orders(payment_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS payment_remote_requests (
  request_id BIGINT NOT NULL AUTO_INCREMENT,
  requester_user_id BIGINT NOT NULL COMMENT 'auth_users 논리 참조',
  target_user_id BIGINT NOT NULL COMMENT 'auth_users 논리 참조',
  payment_id BIGINT NULL,
  amount BIGINT NOT NULL,
  description VARCHAR(200) NULL,
  status ENUM('PENDING','COMPLETED','REJECTED_BY_PAYER','CANCELLED_BY_REQUESTER','EXPIRED') NOT NULL DEFAULT 'PENDING',
  reject_reason VARCHAR(200) NULL,
  expires_at DATETIME NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  completed_at DATETIME NULL,
  PRIMARY KEY (request_id),
  KEY idx_payment_remote_requests_requester (requester_user_id),
  KEY idx_payment_remote_requests_target (target_user_id),
  KEY idx_payment_remote_requests_payment (payment_id),
  KEY idx_payment_remote_requests_status_expires (status, expires_at),
  CONSTRAINT fk_payment_remote_requests_payment FOREIGN KEY (payment_id) REFERENCES payment_orders(payment_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS dutch_pay_sessions (
  session_id BIGINT NOT NULL AUTO_INCREMENT,
  dutch_order_no VARCHAR(64) NOT NULL,
  host_user_id BIGINT NOT NULL COMMENT 'auth_users 논리 참조',
  host_auth_payment_id BIGINT NOT NULL,
  total_amount BIGINT NOT NULL,
  split_method ENUM('EQUAL','CUSTOM') NOT NULL,
  status ENUM('CREATED','IN_PROGRESS','COMPLETED','TIMEOUT_HANDLED','FAILED') NOT NULL DEFAULT 'CREATED',
  timeout_at DATETIME NULL,
  warning_1_sent_at DATETIME NULL,
  warning_2_sent_at DATETIME NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  completed_at DATETIME NULL,
  PRIMARY KEY (session_id),
  UNIQUE KEY uk_dutch_pay_sessions_order_no (dutch_order_no),
  UNIQUE KEY uk_dutch_pay_sessions_host_auth_payment (host_auth_payment_id),
  KEY idx_dutch_pay_sessions_host_user (host_user_id),
  KEY idx_dutch_pay_sessions_status (status),
  CONSTRAINT fk_dutch_pay_sessions_host_auth_payment FOREIGN KEY (host_auth_payment_id) REFERENCES payment_orders(payment_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS dutch_pay_participants (
  participant_id BIGINT NOT NULL AUTO_INCREMENT,
  session_id BIGINT NOT NULL,
  user_id BIGINT NOT NULL COMMENT 'auth_users 논리 참조',
  amount BIGINT NOT NULL,
  payment_id BIGINT NULL,
  status ENUM('INVITED','REJECTED','PENDING','PAID','TIMEOUT','HOST_PAID') NOT NULL DEFAULT 'INVITED',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
  paid_at DATETIME NULL,
  PRIMARY KEY (participant_id),
  UNIQUE KEY uk_dutch_pay_participants_session_user (session_id, user_id),
  KEY idx_dutch_pay_participants_user (user_id),
  KEY idx_dutch_pay_participants_payment (payment_id),
  KEY idx_dutch_pay_participants_status (status),
  CONSTRAINT fk_dutch_pay_participants_session FOREIGN KEY (session_id) REFERENCES dutch_pay_sessions(session_id),
  CONSTRAINT fk_dutch_pay_participants_payment FOREIGN KEY (payment_id) REFERENCES payment_orders(payment_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Add optional same-schema FK-like indexes after both tables exist. Actual FK not added for nullable circular logical columns.
ALTER TABLE payment_orders
  ADD KEY idx_payment_orders_dutch_role (dutch_role),
  ADD KEY idx_payment_orders_payment_type (payment_type);
