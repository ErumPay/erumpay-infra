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
  user_id       BIGINT       NOT NULL AUTO_INCREMENT,
  name          VARCHAR(50)  NOT NULL                COMMENT '평문 (검색 키)',
  phone_number  VARCHAR(255) NOT NULL                COMMENT 'AES-256 암호화',
  birth_date    VARCHAR(255) NOT NULL                COMMENT 'AES-256 암호화 (YYMMDD)',
  created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    DATETIME     NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id),
  UNIQUE KEY uk_simulator_user_name_phone (name, phone_number)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS simulator_card_product (
  product_id    BIGINT       NOT NULL AUTO_INCREMENT,
  card_company  VARCHAR(50)  NOT NULL                COMMENT '영문 enum name (예: SHINHAN)',
  product_name  VARCHAR(100) NOT NULL,
  created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    DATETIME     NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (product_id),
  UNIQUE KEY uk_simulator_card_product_company_name (card_company, product_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS simulator_card (
  card_id              BIGINT       NOT NULL AUTO_INCREMENT,
  user_id              BIGINT       NOT NULL,
  product_id           BIGINT       NOT NULL,
  card_company         VARCHAR(50)  NOT NULL                COMMENT '영문 enum name',
  card_number          VARCHAR(255) NOT NULL                COMMENT 'AES-256 암호화',
  masked_number        VARCHAR(25)  NOT NULL,
  expiry_date          VARCHAR(255) NOT NULL                COMMENT 'AES-256 암호화 (YYMM)',
  cvc                  VARCHAR(255) NOT NULL                COMMENT 'AES-256 암호화',
  password_2digit      VARCHAR(64)  NOT NULL                COMMENT 'SHA-256(password_2digit + card_salt) Base64',
  card_salt            VARCHAR(64)  NOT NULL                COMMENT 'salt (Base64)',
  card_status          ENUM('ACTIVE','LOST','EXPIRED','DELETED') NOT NULL DEFAULT 'ACTIVE',
  created_at           DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at           DATETIME     NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (card_id),
  UNIQUE KEY uk_simulator_card_company_number (card_company, card_number),
  KEY idx_simulator_card_user (user_id),
  KEY idx_simulator_card_product (product_id),
  KEY idx_simulator_card_status (card_status),
  CONSTRAINT fk_simulator_card_user FOREIGN KEY (user_id) REFERENCES simulator_user(user_id),
  CONSTRAINT fk_simulator_card_product FOREIGN KEY (product_id) REFERENCES simulator_card_product(product_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS simulator_card_token (
  token_id                BIGINT       NOT NULL AUTO_INCREMENT,
  card_token              VARCHAR(255) NULL DEFAULT NULL       COMMENT 'AES-256 암호화, 발급 실패 시 NULL',
  card_id                 BIGINT       NOT NULL,
  card_company            VARCHAR(50)  NOT NULL                COMMENT '영문 enum name',
  pg_id                   VARCHAR(20)  NOT NULL,
  issue_idempotency_key   VARCHAR(64)  NOT NULL                COMMENT '발급 멱등성 키',
  delete_idempotency_key  VARCHAR(64)  NULL                    COMMENT '삭제 멱등성 키',
  issue_response_code     VARCHAR(20)  NOT NULL                COMMENT '카드사 발급 응답코드',
  issue_response_message  VARCHAR(255) NOT NULL                COMMENT '카드사 발급 응답메시지',
  delete_response_code    VARCHAR(20)  NULL                    COMMENT '카드사 삭제 응답코드',
  delete_response_message VARCHAR(255) NULL                    COMMENT '카드사 삭제 응답메시지',
  token_status            ENUM('ACTIVE','DELETED') NOT NULL DEFAULT 'ACTIVE',
  active_card_pg          VARCHAR(50) GENERATED ALWAYS AS
                          (CASE WHEN token_status = 'ACTIVE'
                                THEN CONCAT(card_id, '-', pg_id)
                                ELSE NULL END) VIRTUAL
                          COMMENT 'ACTIVE 상태에서만 (card_id, pg_id) 노출, UNIQUE 제약용',
  created_at              DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at              DATETIME     NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (token_id),
  UNIQUE KEY uk_simulator_card_token_token (card_token),
  UNIQUE KEY uk_simulator_card_token_issue_idem (issue_idempotency_key),
  UNIQUE KEY uk_simulator_card_token_delete_idem (delete_idempotency_key),
  UNIQUE KEY uk_simulator_card_token_active_card_pg (active_card_pg),
  KEY idx_simulator_card_token_card (card_id),
  KEY idx_simulator_card_token_status (token_status),
  CONSTRAINT fk_simulator_card_token_card FOREIGN KEY (card_id) REFERENCES simulator_card(card_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS simulator_pre_approval (
  pre_approval_id           BIGINT       NOT NULL AUTO_INCREMENT,
  card_id                   BIGINT       NOT NULL,
  card_company              VARCHAR(50)  NOT NULL                COMMENT '영문 enum name',
  pg_id                     VARCHAR(20)  NOT NULL,
  pg_txn_id                 BIGINT       NOT NULL                COMMENT 'PG 거래 ID',
  authorize_idempotency_key VARCHAR(64)  NOT NULL                COMMENT '가승인 멱등성 키',
  cancel_idempotency_key    VARCHAR(64)  NULL                    COMMENT '취소 멱등성 키',
  original_amount           BIGINT       NOT NULL,
  approved_amount           BIGINT       NOT NULL,
  pre_approval_number       VARCHAR(50)  NOT NULL                COMMENT '시뮬레이터 발급 가승인 번호',
  pre_approval_status       ENUM('AUTHORIZED','CANCELED','FAILED') NOT NULL DEFAULT 'AUTHORIZED',
  response_code             VARCHAR(20)  NOT NULL                COMMENT '카드사 응답코드',
  response_message          VARCHAR(255) NOT NULL                COMMENT '카드사 응답메시지',
  created_at                DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at                DATETIME     NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (pre_approval_id),
  UNIQUE KEY uk_simulator_pre_approval_auth_idem (authorize_idempotency_key),
  UNIQUE KEY uk_simulator_pre_approval_cancel_idem (cancel_idempotency_key),
  UNIQUE KEY uk_simulator_pre_approval_number (pre_approval_number),
  KEY idx_simulator_pre_approval_card (card_id),
  KEY idx_simulator_pre_approval_status (pre_approval_status),
  CONSTRAINT fk_simulator_pre_approval_card FOREIGN KEY (card_id) REFERENCES simulator_card(card_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS simulator_payment_history (
  payment_id              BIGINT       NOT NULL AUTO_INCREMENT,
  card_id                 BIGINT       NOT NULL,
  card_company            VARCHAR(50)  NOT NULL                COMMENT '영문 enum name',
  pg_id                   VARCHAR(20)  NOT NULL,
  pg_txn_id               BIGINT       NOT NULL                COMMENT 'PG 거래 ID',
  origin_pg_txn_id        BIGINT       NULL                    COMMENT '원거래 PG 거래 ID (취소 row만 사용)',
  idempotency_key         VARCHAR(64)  NOT NULL                COMMENT '작업 멱등성 키 (이 row의 작업)',
  origin_idempotency_key  VARCHAR(64)  NULL                    COMMENT '원거래 멱등성 키 (취소 row만 사용)',
  payment_status          ENUM('APPROVED','CANCELED','FAILED') NOT NULL DEFAULT 'APPROVED',
  original_amount         BIGINT       NOT NULL,
  approved_amount         BIGINT       NOT NULL,
  performance_date        DATETIME     NOT NULL                COMMENT '실적 산정 기준일',
  approval_number         VARCHAR(50)  NOT NULL                COMMENT '시뮬레이터 발급 승인번호',
  response_code           VARCHAR(20)  NOT NULL                COMMENT '카드사 응답코드',
  response_message        VARCHAR(255) NOT NULL                COMMENT '카드사 응답메시지',
  created_at              DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (payment_id),
  UNIQUE KEY uk_simulator_payment_history_idempotency (idempotency_key),
  UNIQUE KEY uk_simulator_payment_history_approval_number (approval_number),
  KEY idx_simulator_payment_history_perf_date (performance_date),
  KEY idx_simulator_payment_history_origin_idem (origin_idempotency_key),
  KEY idx_simulator_payment_history_card_perf_status (card_id, performance_date, payment_status),
  CONSTRAINT fk_simulator_payment_history_card FOREIGN KEY (card_id) REFERENCES simulator_card(card_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS simulator_response_code (
  code_id          BIGINT       NOT NULL AUTO_INCREMENT,
  category         ENUM('TOKEN','CARD','PAYMENT','TRANSACTION','USER','SYSTEM') NOT NULL COMMENT '응답 카테고리',
  response_code    VARCHAR(20)  NOT NULL                COMMENT '카드사 응답코드',
  response_message VARCHAR(255) NOT NULL                COMMENT '카드사 응답메시지',
  response_type    ENUM(
                     'SUCCESS',
                     'CARD_LOST','CARD_EXPIRED','CARD_DELETED',
                     'CARD_INVALID_INFO','CARD_INVALID_PASSWORD',
                     'TOKEN_NOT_FOUND','TOKEN_DUPLICATE',
                     'PAYMENT_LIMIT_EXCEEDED','PAYMENT_INSUFFICIENT_BALANCE','PAYMENT_REJECTED',
                     'TRANSACTION_NOT_FOUND','TRANSACTION_ALREADY_PROCESSED',
                     'USER_NOT_FOUND','USER_INVALID_INFO',
                     'SYSTEM_ERROR'
                   ) NOT NULL,
  PRIMARY KEY (code_id),
  UNIQUE KEY uk_simulator_response_code_code (response_code),
  UNIQUE KEY uk_simulator_response_code_category_type (category, response_type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS simulator_config (
  config_id      BIGINT        NOT NULL AUTO_INCREMENT,
  approval_rate  DECIMAL(5,2)  NOT NULL COMMENT '결제/가승인 승인률 (%)',
  delay_ms       INT           NOT NULL DEFAULT 0      COMMENT '응답 지연 (ms), 타임아웃 테스트용',
  reject_pattern VARCHAR(200)  NULL                    COMMENT '거절 카드번호 정규식 패턴',
  PRIMARY KEY (config_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
