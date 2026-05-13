-- EroomPay MSA MySQL DDL
-- Target: MySQL 8.0+
SET NAMES utf8mb4;
SET time_zone = '+09:00';

CREATE DATABASE IF NOT EXISTS notification_db DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
-- =========================================================
-- notification_db (notification-service)
-- =========================================================
USE notification_db;

CREATE TABLE IF NOT EXISTS notifications (
  notification_id BIGINT NOT NULL AUTO_INCREMENT,
  user_id BIGINT NOT NULL COMMENT 'auth_users 논리 참조',
  type ENUM('PAYMENT_DONE','PAYMENT_CANCELED','CARD_REGISTERED','CARD_DELETED','REMOTE_REQUEST','REMOTE_APPROVED','REMOTE_REJECTED','DUTCHPAY_INVITE','DUTCHPAY_JOINED','DUTCHPAY_TIMEOUT','FRIEND_REQUEST') NOT NULL,
  title VARCHAR(100) NOT NULL,
  content VARCHAR(500) NOT NULL,
  is_read BOOLEAN NOT NULL DEFAULT FALSE,
  channel ENUM('PUSH','IN_APP') NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  failure_code VARCHAR(50) NULL,
  payment_id BIGINT NULL COMMENT 'payment_orders.payment_id 논리 참조',
  read_at DATETIME NULL,
  updated_at DATETIME NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (notification_id),
  KEY idx_notifications_user_created (user_id, created_at),
  KEY idx_notifications_user_read (user_id, is_read),
  KEY idx_notifications_payment (payment_id),
  KEY idx_notifications_type (type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS notification_preferences (
  preference_id BIGINT NOT NULL AUTO_INCREMENT,
  user_id BIGINT NOT NULL COMMENT 'auth_users 논리 참조, 1:1',
  push_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  card_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  payment_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  dutchpay_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  remote_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  friend_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  night_blocked BOOLEAN NOT NULL DEFAULT FALSE,
  updated_at DATETIME NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
  created_at DATETIME NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (preference_id),
  UNIQUE KEY uk_notification_preferences_user (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
