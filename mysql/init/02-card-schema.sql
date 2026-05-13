-- EroomPay MSA MySQL DDL
-- Target: MySQL 8.0+
SET NAMES utf8mb4;
SET time_zone = '+09:00';

CREATE DATABASE IF NOT EXISTS card_db DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
-- =========================================================
-- card_db (card-service)
-- =========================================================
USE card_db;

CREATE TABLE IF NOT EXISTS card_product (
  card_product_id BIGINT NOT NULL AUTO_INCREMENT,
  mock_bin VARCHAR(6) NOT NULL COMMENT '카드번호 앞 6자리 mock 매칭 키',
  card_company VARCHAR(50) NOT NULL,
  card_name VARCHAR(100) NOT NULL,
  card_type ENUM('CREDIT','CHECK') NOT NULL,
  annual_fee BIGINT NULL,
  image_url VARCHAR(500) NULL,
  source_card_id VARCHAR(50) NOT NULL COMMENT '카드고릴라 card_id',
  source_url VARCHAR(500) NULL,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (card_product_id),
  UNIQUE KEY uk_card_product_mock_bin (mock_bin),
  UNIQUE KEY uk_card_product_source_card_id (source_card_id),
  KEY idx_card_product_company_name (card_company, card_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS card_registered (
  card_id BIGINT NOT NULL AUTO_INCREMENT,
  user_id BIGINT NOT NULL COMMENT 'auth_db.auth_users.user_id 논리 참조',
  card_product_id BIGINT NOT NULL,
  encrypted_billing_key VARCHAR(255) NOT NULL COMMENT 'PG 발급 빌링키 암호화 저장',
  masked_number VARCHAR(20) NOT NULL,
  card_alias VARCHAR(50) NULL,
  expiry_ym CHAR(6) NOT NULL COMMENT 'YYYYMM',
  is_default BOOLEAN NOT NULL DEFAULT FALSE,
  status ENUM('ACTIVE','PAUSED','EXPIRED','DELETED') NOT NULL DEFAULT 'ACTIVE',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at DATETIME NULL,
  default_active_user_id BIGINT GENERATED ALWAYS AS (CASE WHEN is_default = TRUE AND status = 'ACTIVE' AND deleted_at IS NULL THEN user_id ELSE NULL END) STORED COMMENT '사용자별 활성 기본카드 1개 보장용',
  PRIMARY KEY (card_id),
  UNIQUE KEY uk_card_registered_billing_key (encrypted_billing_key),
  UNIQUE KEY uk_card_registered_default_active_user (default_active_user_id),
  KEY idx_card_registered_user (user_id),
  KEY idx_card_registered_product (card_product_id),
  KEY idx_card_registered_status (status),
  CONSTRAINT fk_card_registered_product FOREIGN KEY (card_product_id) REFERENCES card_product(card_product_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS card_performance (
  perf_id BIGINT NOT NULL AUTO_INCREMENT,
  user_id BIGINT NOT NULL COMMENT 'auth_users 논리 참조',
  card_id BIGINT NOT NULL,
  year_month CHAR(6) NOT NULL COMMENT 'YYYYMM',
  amount BIGINT NOT NULL DEFAULT 0,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (perf_id),
  UNIQUE KEY uk_card_performance_user_card_month (user_id, card_id, year_month),
  KEY idx_card_performance_card (card_id),
  CONSTRAINT fk_card_performance_card FOREIGN KEY (card_id) REFERENCES card_registered(card_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS card_benefit (
  benefit_id BIGINT NOT NULL AUTO_INCREMENT,
  card_product_id BIGINT NOT NULL,
  service_category ENUM('FOOD','CAFE','GROCERY','CVS','SHOPPING','AUTO','TRANSIT','TAXI','HEALTH','PHARMACY','BEAUTY','LEISURE','FITNESS','EDU','TELECOM','UTILITY','TRAVEL','AIRLINE','INSURANCE','ETC') NOT NULL,
  benefit_type ENUM('DISCOUNT','CASHBACK','MILEAGE') NOT NULL,
  min_amount BIGINT NULL,
  time_start TIME NULL,
  time_end TIME NULL,
  day_condition ENUM('ALL','WEEKDAY','WEEKEND') NOT NULL DEFAULT 'ALL',
  benefit_desc VARCHAR(500) NULL,
  priority INT NOT NULL DEFAULT 0,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (benefit_id),
  KEY idx_card_benefit_product (card_product_id),
  KEY idx_card_benefit_category (service_category),
  CONSTRAINT fk_card_benefit_product FOREIGN KEY (card_product_id) REFERENCES card_product(card_product_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS card_benefit_tier (
  tier_id BIGINT NOT NULL AUTO_INCREMENT,
  benefit_id BIGINT NOT NULL,
  min_prev_month_usage BIGINT NOT NULL DEFAULT 0,
  max_prev_month_usage BIGINT NULL,
  rate DECIMAL(5,2) NULL,
  flat_amount BIGINT NULL,
  max_benefit_per_use BIGINT NULL,
  daily_limit_count INT NULL,
  daily_limit_amount BIGINT NULL,
  monthly_limit_count INT NULL,
  monthly_limit_amount BIGINT NULL,
  yearly_limit_count INT NULL,
  yearly_limit_amount BIGINT NULL,
  tier_desc VARCHAR(255) NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (tier_id),
  UNIQUE KEY uk_card_benefit_tier_benefit_min_usage (benefit_id, min_prev_month_usage),
  KEY idx_card_benefit_tier_benefit (benefit_id),
  CONSTRAINT fk_card_benefit_tier_benefit FOREIGN KEY (benefit_id) REFERENCES card_benefit(benefit_id),
  CONSTRAINT chk_card_benefit_tier_rate_xor_flat CHECK ((rate IS NOT NULL AND flat_amount IS NULL) OR (rate IS NULL AND flat_amount IS NOT NULL))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS card_benefit_usage (
  usage_id BIGINT NOT NULL AUTO_INCREMENT,
  payment_id BIGINT NOT NULL COMMENT 'payment_db.payment_orders.payment_id 논리 참조',
  user_id BIGINT NOT NULL COMMENT 'auth_users 논리 참조',
  card_id BIGINT NOT NULL,
  benefit_id BIGINT NOT NULL,
  tier_id BIGINT NOT NULL,
  approved_amount INT NOT NULL,
  benefit_amount INT NOT NULL,
  approved_at DATETIME NOT NULL,
  status ENUM('APPROVED','CANCELED') NOT NULL DEFAULT 'APPROVED',
  canceled_at DATETIME NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (usage_id),
  UNIQUE KEY uk_card_benefit_usage_payment_card_benefit_tier (payment_id, card_id, benefit_id, tier_id),
  KEY idx_card_benefit_usage_user_date (user_id, approved_at),
  KEY idx_card_benefit_usage_card (card_id),
  KEY idx_card_benefit_usage_benefit (benefit_id),
  KEY idx_card_benefit_usage_tier (tier_id),
  CONSTRAINT fk_card_benefit_usage_card FOREIGN KEY (card_id) REFERENCES card_registered(card_id),
  CONSTRAINT fk_card_benefit_usage_benefit FOREIGN KEY (benefit_id) REFERENCES card_benefit(benefit_id),
  CONSTRAINT fk_card_benefit_usage_tier FOREIGN KEY (tier_id) REFERENCES card_benefit_tier(tier_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
