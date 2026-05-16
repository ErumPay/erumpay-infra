-- ErumPay recommend_db merchant keyword override seed
-- source: used_brand_names from card_gorilla seed dry-run
-- scope: representative brand names only; alias table is intentionally out of MVP scope.
-- note: recommendation-service should normalize whitespace when comparing merchant names and keywords.

SET NAMES utf8mb4;
USE recommend_db;

START TRANSACTION;

INSERT INTO recommend_merchant_keyword_override (
  keyword,
  override_category,
  priority,
  created_at,
  is_active
)
VALUES
  ('11번가', 'SHOPPING', 100, NOW(), TRUE),
  ('CGV', 'LEISURE', 100, NOW(), TRUE),
  ('CU', 'CVS', 100, NOW(), TRUE),
  ('GS25', 'CVS', 100, NOW(), TRUE),
  ('GS칼텍스', 'AUTO', 100, NOW(), TRUE),
  ('G마켓', 'SHOPPING', 100, NOW(), TRUE),
  ('KT', 'TELECOM', 100, NOW(), TRUE),
  ('LG U+', 'TELECOM', 100, NOW(), TRUE),
  ('S-OIL', 'AUTO', 100, NOW(), TRUE),
  ('SKT', 'TELECOM', 100, NOW(), TRUE),
  ('SK에너지', 'AUTO', 100, NOW(), TRUE),
  ('SSG.COM', 'SHOPPING', 100, NOW(), TRUE),
  ('VIPS', 'FOOD', 100, NOW(), TRUE),
  ('넷플릭스', 'ETC', 100, NOW(), TRUE),
  ('디즈니플러스', 'ETC', 100, NOW(), TRUE),
  ('땡겨요', 'FOOD', 100, NOW(), TRUE),
  ('뚜레쥬르', 'FOOD', 100, NOW(), TRUE),
  ('롯데마트', 'GROCERY', 100, NOW(), TRUE),
  ('롯데시네마', 'LEISURE', 100, NOW(), TRUE),
  ('롯데월드', 'LEISURE', 100, NOW(), TRUE),
  ('마켓컬리', 'SHOPPING', 100, NOW(), TRUE),
  ('메가박스', 'LEISURE', 100, NOW(), TRUE),
  ('메가커피', 'CAFE', 100, NOW(), TRUE),
  ('배달의 민족', 'FOOD', 100, NOW(), TRUE),
  ('빽다방', 'CAFE', 100, NOW(), TRUE),
  ('세븐일레븐', 'CVS', 100, NOW(), TRUE),
  ('스타벅스', 'CAFE', 100, NOW(), TRUE),
  ('신세계백화점', 'SHOPPING', 100, NOW(), TRUE),
  ('아웃백', 'FOOD', 100, NOW(), TRUE),
  ('에버랜드', 'LEISURE', 100, NOW(), TRUE),
  ('엔제리너스', 'CAFE', 100, NOW(), TRUE),
  ('올리브영', 'BEAUTY', 100, NOW(), TRUE),
  ('요기요', 'FOOD', 100, NOW(), TRUE),
  ('유튜브', 'ETC', 100, NOW(), TRUE),
  ('이디야', 'CAFE', 100, NOW(), TRUE),
  ('이마트', 'GROCERY', 100, NOW(), TRUE),
  ('이마트24', 'CVS', 100, NOW(), TRUE),
  ('지니뮤직', 'ETC', 100, NOW(), TRUE),
  ('커피빈', 'CAFE', 100, NOW(), TRUE),
  ('컴포즈커피', 'CAFE', 100, NOW(), TRUE),
  ('쿠팡이츠', 'FOOD', 100, NOW(), TRUE),
  ('투썸플레이스', 'CAFE', 100, NOW(), TRUE),
  ('폴바셋', 'CAFE', 100, NOW(), TRUE),
  ('할리스', 'CAFE', 100, NOW(), TRUE),
  ('현대오일뱅크', 'AUTO', 100, NOW(), TRUE),
  ('홈플러스', 'GROCERY', 100, NOW(), TRUE)
ON DUPLICATE KEY UPDATE
  override_category = VALUES(override_category),
  priority = VALUES(priority),
  is_active = VALUES(is_active);

COMMIT;
