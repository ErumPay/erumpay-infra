-- EroomPay MSA MySQL DDL
-- Target: MySQL 8.0+
SET NAMES utf8mb4;
SET time_zone = '+09:00';

CREATE DATABASE IF NOT EXISTS recommend_db DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
-- =========================================================
-- recommend_db (recommendation-service)
-- =========================================================
USE recommend_db;

CREATE TABLE IF NOT EXISTS recommend_results (
  result_id BIGINT NOT NULL AUTO_INCREMENT,
  payment_id BIGINT NOT NULL COMMENT 'payment_db.payment_orders.payment_id 논리 참조',
  strategy_type ENUM('BENEFIT_SINGLE','BENEFIT_SPLIT','PERF_SINGLE','PERF_SPLIT') NOT NULL,
  recommended_cards JSON NOT NULL,
  total_benefit_amount BIGINT NOT NULL DEFAULT 0,
  is_selected BOOLEAN NOT NULL DEFAULT FALSE,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (result_id),
  UNIQUE KEY uk_recommend_results_payment_strategy (payment_id, strategy_type),
  KEY idx_recommend_results_payment (payment_id),
  CONSTRAINT chk_recommend_results_json CHECK (JSON_VALID(recommended_cards))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS recommend_mcc_mapping (
  mapping_id BIGINT NOT NULL AUTO_INCREMENT,
  mcc_code CHAR(4) NOT NULL COMMENT 'ISO 18245',
  mcc_description VARCHAR(100) NULL,
  service_category ENUM('FOOD','CAFE','GROCERY','CVS','SHOPPING','AUTO','TRANSIT','TAXI','HEALTH','PHARMACY','BEAUTY','LEISURE','FITNESS','EDU','TELECOM','UTILITY','TRAVEL','AIRLINE','INSURANCE','ETC','ALL') NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  PRIMARY KEY (mapping_id),
  UNIQUE KEY uk_recommend_mcc_mapping_mcc_code (mcc_code),
  KEY idx_recommend_mcc_mapping_category (service_category),
  KEY idx_recommend_mcc_mapping_active (is_active)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS recommend_merchant_keyword_override (
  override_id BIGINT NOT NULL AUTO_INCREMENT,
  keyword VARCHAR(100) NOT NULL,
  override_category ENUM('FOOD','CAFE','GROCERY','CVS','SHOPPING','AUTO','TRANSIT','TAXI','HEALTH','PHARMACY','BEAUTY','LEISURE','FITNESS','EDU','TELECOM','UTILITY','TRAVEL','AIRLINE','INSURANCE','ETC','ALL') NOT NULL,
  priority INT NOT NULL DEFAULT 0,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  PRIMARY KEY (override_id),
  UNIQUE KEY uk_recommend_merchant_keyword_override_keyword (keyword),
  KEY idx_recommend_merchant_keyword_override_priority (is_active, priority)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
