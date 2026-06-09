-- ErumPay PG merchant dev seed

SET NAMES utf8mb4;
USE pg_merchant_db;

INSERT INTO pg_merchants (
  merchant_id,
  merchant_name,
  business_number,
  owner_name,
  contact_phone,
  business_address,
  category_name,
  mcc_code,
  api_key,
  api_key_status,
  api_key_issued_at,
  api_key_rotated_at,
  fee_rate,
  settlement_account,
  status,
  updated_at,
  suspend_reason,
  deleted_at,
  created_at
)
VALUES (
  101,
  '이룸카페 강남점',
  '123-45-67890',
  '이루미',
  '02-1234-5678',
  '서울특별시 강남구 테헤란로 123',
  '카페',
  '5811',
  'dev-merchant-api-key-101',
  'ACTIVE',
  NOW(),
  NULL,
  1.50,
  'dev-settlement-account-101',
  'ACTIVE',
  NOW(),
  NULL,
  NULL,
  NOW()
)
ON DUPLICATE KEY UPDATE
  merchant_name = VALUES(merchant_name),
  owner_name = VALUES(owner_name),
  contact_phone = VALUES(contact_phone),
  business_address = VALUES(business_address),
  category_name = VALUES(category_name),
  mcc_code = VALUES(mcc_code),
  api_key_status = VALUES(api_key_status),
  fee_rate = VALUES(fee_rate),
  settlement_account = VALUES(settlement_account),
  status = VALUES(status),
  updated_at = NOW(),
  suspend_reason = NULL,
  deleted_at = NULL;
