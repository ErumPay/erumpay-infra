-- EroomPay MSA MySQL DDL
-- Target: MySQL 8.0+
SET NAMES utf8mb4;
SET time_zone = '+09:00';

CREATE DATABASE IF NOT EXISTS auth_db DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
-- =========================================================
-- auth_db (auth-service)
-- =========================================================
USE auth_db;

CREATE TABLE IF NOT EXISTS auth_users (
  user_id BIGINT NOT NULL AUTO_INCREMENT COMMENT '회원 고유번호',
  kakao_oauth_id VARCHAR(100) NOT NULL COMMENT '카카오 OAuth ID, 탈퇴 시 유지',
  phone_number VARCHAR(64) NULL COMMENT 'AES-256 암호화 전화번호',
  phone_number_hash CHAR(64) NOT NULL COMMENT 'SHA-256(전화번호 + 고정 salt), 중복가입 체크용',
  name VARCHAR(50) NULL COMMENT '이름, PENDING 상태에서는 NULL 허용',
  birth_date VARCHAR(255) NULL COMMENT 'AES-256 암호화 생년월일',
  status ENUM('PENDING','ACTIVE','SUSPENDED','WITHDRAWN') NOT NULL DEFAULT 'PENDING',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
  withdrawn_at DATETIME NULL,
  service_terms_agreed_at DATETIME NOT NULL,
  privacy_terms_agreed_at DATETIME NOT NULL,
  marketing_terms_agreed_at DATETIME NULL,
  PRIMARY KEY (user_id),
  UNIQUE KEY uk_auth_users_kakao_oauth_id (kakao_oauth_id),
  UNIQUE KEY uk_auth_users_phone_hash (phone_number_hash),
  KEY idx_auth_users_status (status),
  KEY idx_auth_users_created_at (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS auth_pin (
  pin_id BIGINT NOT NULL AUTO_INCREMENT,
  user_id BIGINT NOT NULL COMMENT 'auth_users.user_id',
  pin_hash VARCHAR(255) NOT NULL COMMENT 'PIN 해시',
  pin_salt VARCHAR(128) NOT NULL COMMENT '고유 랜덤 salt',
  fail_count INT NOT NULL DEFAULT 0,
  fail_last_at DATETIME NULL,
  locked_until DATETIME NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
  deleted_at DATETIME NULL,
  active_user_id BIGINT GENERATED ALWAYS AS (CASE WHEN deleted_at IS NULL THEN user_id ELSE NULL END) STORED COMMENT '활성 PIN 회원당 1개 보장용',
  PRIMARY KEY (pin_id),
  UNIQUE KEY uk_auth_pin_active_user (active_user_id),
  KEY idx_auth_pin_user_id (user_id),
  CONSTRAINT fk_auth_pin_user FOREIGN KEY (user_id) REFERENCES auth_users(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS auth_refresh_tokens (
  token_id BIGINT NOT NULL AUTO_INCREMENT,
  user_id BIGINT NOT NULL,
  token_hash VARCHAR(255) NOT NULL COMMENT '원본 저장 금지',
  device_info VARCHAR(200) NULL,
  expires_at DATETIME NOT NULL,
  is_revoked BOOLEAN NOT NULL DEFAULT FALSE,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (token_id),
  UNIQUE KEY uk_auth_refresh_tokens_hash (token_hash),
  KEY idx_auth_refresh_tokens_user (user_id),
  KEY idx_auth_refresh_tokens_expires (expires_at),
  CONSTRAINT fk_auth_refresh_tokens_user FOREIGN KEY (user_id) REFERENCES auth_users(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS auth_sms_verifications (
  verification_id BIGINT NOT NULL AUTO_INCREMENT,
  user_id BIGINT NULL COMMENT '회원가입 전 인증 시 NULL 허용',
  phone_number VARCHAR(255) NOT NULL COMMENT 'AES-256 암호화 전화번호',
  phone_number_hash CHAR(64) NOT NULL,
  verification_code VARCHAR(10) NOT NULL,
  is_verified BOOLEAN NOT NULL DEFAULT FALSE,
  expires_at DATETIME NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  deleted_at DATETIME NULL,
  PRIMARY KEY (verification_id),
  KEY idx_auth_sms_user (user_id),
  KEY idx_auth_sms_phone_hash (phone_number_hash),
  KEY idx_auth_sms_expires (expires_at),
  CONSTRAINT fk_auth_sms_user FOREIGN KEY (user_id) REFERENCES auth_users(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS friend_relations (
  relation_id BIGINT NOT NULL AUTO_INCREMENT,
  user_id BIGINT NOT NULL COMMENT '요청자',
  friend_user_id BIGINT NOT NULL COMMENT '대상',
  status ENUM('PENDING','ACCEPTED','DELETED') NOT NULL DEFAULT 'PENDING',
  is_favorite BOOLEAN NOT NULL DEFAULT FALSE,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
  deleted_at DATETIME NULL,
  PRIMARY KEY (relation_id),
  UNIQUE KEY uk_friend_relations_pair (user_id, friend_user_id),
  KEY idx_friend_relations_friend (friend_user_id),
  KEY idx_friend_relations_status (status),
  CONSTRAINT fk_friend_relations_user FOREIGN KEY (user_id) REFERENCES auth_users(user_id),
  CONSTRAINT fk_friend_relations_friend FOREIGN KEY (friend_user_id) REFERENCES auth_users(user_id),
  CONSTRAINT chk_friend_relations_not_self CHECK (user_id <> friend_user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS friend_add_links (
  invite_id BIGINT NOT NULL AUTO_INCREMENT,
  inviter_user_id BIGINT NOT NULL,
  invitee_user_id BIGINT NULL,
  invite_token VARCHAR(255) NOT NULL,
  expires_at DATETIME NOT NULL,
  is_used BOOLEAN NOT NULL DEFAULT FALSE,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (invite_id),
  UNIQUE KEY uk_friend_add_links_token (invite_token),
  KEY idx_friend_add_links_inviter (inviter_user_id),
  KEY idx_friend_add_links_invitee (invitee_user_id),
  KEY idx_friend_add_links_expires (expires_at),
  CONSTRAINT fk_friend_add_links_inviter FOREIGN KEY (inviter_user_id) REFERENCES auth_users(user_id),
  CONSTRAINT fk_friend_add_links_invitee FOREIGN KEY (invitee_user_id) REFERENCES auth_users(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS auth_device_tokens (
  device_token_id BIGINT NOT NULL AUTO_INCREMENT,
  user_id BIGINT NOT NULL,
  fcm_token VARCHAR(255) NOT NULL,
  device_os ENUM('ANDROID','IOS') NOT NULL,
  device_id VARCHAR(100) NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (device_token_id),
  UNIQUE KEY uk_auth_device_tokens_fcm (fcm_token),
  UNIQUE KEY uk_auth_device_tokens_user_device (user_id, device_id),
  KEY idx_auth_device_tokens_user (user_id),
  CONSTRAINT fk_auth_device_tokens_user FOREIGN KEY (user_id) REFERENCES auth_users(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
