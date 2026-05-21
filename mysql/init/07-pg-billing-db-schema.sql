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
  billing_key_id     BIGINT       NOT NULL AUTO_INCREMENT,
  idempotency_key    VARCHAR(64)  NOT NULL                COMMENT '카드사 요청 멱등성 키, 호출 전 생성',
  billing_key        VARCHAR(32)  NULL DEFAULT NULL       COMMENT 'UUID v4 (하이픈 제외 32자), ACTIVE 전환 시 부여',
  pay_card_id        BIGINT       NOT NULL                COMMENT 'card_db.card_registered.card_id 논리 참조',
  card_token         VARCHAR(255) NULL DEFAULT NULL       COMMENT '카드사 발급 토큰, AES-256 암호화',
  masked_number      VARCHAR(25)  NULL DEFAULT NULL,
  card_company       VARCHAR(50)  NULL DEFAULT NULL,
  status             ENUM('PENDING','ACTIVE','DELETED','FAILED') NOT NULL DEFAULT 'PENDING'
                     COMMENT 'PENDING: 카드사 응답 대기, ACTIVE: 사용 가능, DELETED: 비활성화, FAILED: 발급 실패',
  live_pay_card_id   BIGINT GENERATED ALWAYS AS
                     (CASE WHEN status IN ('PENDING','ACTIVE') THEN pay_card_id ELSE NULL END) VIRTUAL
                     COMMENT '진행 중(PENDING) 또는 활성(ACTIVE) 상태에서만 pay_card_id 노출. 동시 발급 및 중복 ACTIVE 차단용',
  created_at         DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at         DATETIME     NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (billing_key_id),
  UNIQUE KEY uk_pg_billing_keys_idempotency (idempotency_key),
  UNIQUE KEY uk_pg_billing_keys_billing_key (billing_key),
  UNIQUE KEY uk_pg_billing_keys_live_card (live_pay_card_id),
  KEY idx_pg_billing_keys_status_created (status, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
