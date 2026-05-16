-- ErumPay recommend_db MCC mapping seed
-- note: unmapped MCC values should fall back to ETC in recommendation-service.
-- note: MCC 4511 appears in both TRANSIT and AIRLINE in the PDF; AIRLINE is applied last.

SET NAMES utf8mb4;
USE recommend_db;

DELIMITER $$

DROP PROCEDURE IF EXISTS seed_recommend_mcc_mapping $$

CREATE PROCEDURE seed_recommend_mcc_mapping(
  IN p_start INT,
  IN p_end INT,
  IN p_description VARCHAR(100),
  IN p_category VARCHAR(20)
)
BEGIN
  DECLARE v_code INT DEFAULT p_start;

  WHILE v_code <= p_end DO
    INSERT INTO recommend_mcc_mapping (
      mcc_code,
      mcc_description,
      service_category,
      created_at,
      updated_at,
      is_active
    )
    VALUES (
      LPAD(v_code, 4, '0'),
      p_description,
      p_category,
      NOW(),
      NOW(),
      TRUE
    )
    ON DUPLICATE KEY UPDATE
      mcc_description = p_description,
      service_category = p_category,
      updated_at = NOW(),
      is_active = TRUE;

    SET v_code = v_code + 1;
  END WHILE;
END $$

DELIMITER ;

START TRANSACTION;

CALL seed_recommend_mcc_mapping(3000, 3299, '항공사 범위', 'AIRLINE');
CALL seed_recommend_mcc_mapping(3500, 3999, '여행/숙박 범위', 'TRAVEL');
CALL seed_recommend_mcc_mapping(5300, 5399, '쇼핑 범위', 'SHOPPING');
CALL seed_recommend_mcc_mapping(5600, 5699, '의류/잡화 쇼핑 범위', 'SHOPPING');
CALL seed_recommend_mcc_mapping(5900, 5999, '소매/전문점 쇼핑 범위', 'SHOPPING');

CALL seed_recommend_mcc_mapping(5812, 5812, '식당', 'FOOD');
CALL seed_recommend_mcc_mapping(5813, 5813, '주점', 'FOOD');
CALL seed_recommend_mcc_mapping(5814, 5814, '패스트푸드', 'FOOD');

CALL seed_recommend_mcc_mapping(5811, 5811, '카페/베이커리', 'CAFE');

CALL seed_recommend_mcc_mapping(5411, 5411, '슈퍼마켓', 'GROCERY');
CALL seed_recommend_mcc_mapping(5422, 5422, '정육점', 'GROCERY');
CALL seed_recommend_mcc_mapping(5441, 5441, '제과점', 'GROCERY');
CALL seed_recommend_mcc_mapping(5451, 5451, '유제품/식료품', 'GROCERY');
CALL seed_recommend_mcc_mapping(5462, 5462, '베이커리/제과점', 'GROCERY');

CALL seed_recommend_mcc_mapping(5331, 5331, '편의점/잡화점', 'CVS');
CALL seed_recommend_mcc_mapping(5399, 5399, '편의점/잡화점', 'CVS');

CALL seed_recommend_mcc_mapping(5511, 5511, '자동차 판매', 'AUTO');
CALL seed_recommend_mcc_mapping(5521, 5521, '중고차 판매', 'AUTO');
CALL seed_recommend_mcc_mapping(5541, 5541, '주유소', 'AUTO');
CALL seed_recommend_mcc_mapping(5542, 5542, '무인 주유소', 'AUTO');
CALL seed_recommend_mcc_mapping(5571, 5571, '오토바이 판매', 'AUTO');
CALL seed_recommend_mcc_mapping(5599, 5599, '자동차 판매/수리', 'AUTO');

CALL seed_recommend_mcc_mapping(4011, 4011, '기차', 'TRANSIT');
CALL seed_recommend_mcc_mapping(4111, 4111, '버스', 'TRANSIT');
CALL seed_recommend_mcc_mapping(4112, 4112, '철도/여객', 'TRANSIT');
CALL seed_recommend_mcc_mapping(4131, 4131, '버스 노선', 'TRANSIT');
CALL seed_recommend_mcc_mapping(4411, 4411, '선박', 'TRANSIT');
CALL seed_recommend_mcc_mapping(4511, 4511, '항공/여객', 'TRANSIT');

CALL seed_recommend_mcc_mapping(4121, 4121, '택시', 'TAXI');
CALL seed_recommend_mcc_mapping(7512, 7512, '렌터카', 'TAXI');
CALL seed_recommend_mcc_mapping(7513, 7513, '트럭/차량 렌탈', 'TAXI');

CALL seed_recommend_mcc_mapping(8011, 8011, '병원', 'HEALTH');
CALL seed_recommend_mcc_mapping(8021, 8021, '치과', 'HEALTH');
CALL seed_recommend_mcc_mapping(8031, 8031, '정형외과', 'HEALTH');
CALL seed_recommend_mcc_mapping(8049, 8049, '의료 서비스', 'HEALTH');
CALL seed_recommend_mcc_mapping(8062, 8062, '종합병원', 'HEALTH');
CALL seed_recommend_mcc_mapping(8099, 8099, '의료/보건 서비스', 'HEALTH');

CALL seed_recommend_mcc_mapping(5912, 5912, '약국', 'PHARMACY');

CALL seed_recommend_mcc_mapping(7230, 7230, '미용실', 'BEAUTY');
CALL seed_recommend_mcc_mapping(7297, 7297, '스파/마사지', 'BEAUTY');
CALL seed_recommend_mcc_mapping(5977, 5977, '화장품', 'BEAUTY');

CALL seed_recommend_mcc_mapping(7832, 7832, '영화관', 'LEISURE');
CALL seed_recommend_mcc_mapping(7922, 7922, '공연', 'LEISURE');
CALL seed_recommend_mcc_mapping(7991, 7991, '관광/전시', 'LEISURE');
CALL seed_recommend_mcc_mapping(7993, 7993, '게임/오락', 'LEISURE');
CALL seed_recommend_mcc_mapping(7996, 7996, '테마파크', 'LEISURE');
CALL seed_recommend_mcc_mapping(7999, 7999, '레저', 'LEISURE');

CALL seed_recommend_mcc_mapping(7941, 7941, '스포츠 클럽', 'FITNESS');
CALL seed_recommend_mcc_mapping(7992, 7992, '골프', 'FITNESS');
CALL seed_recommend_mcc_mapping(7997, 7997, '헬스장', 'FITNESS');
CALL seed_recommend_mcc_mapping(5655, 5655, '스포츠용품', 'FITNESS');

CALL seed_recommend_mcc_mapping(8211, 8211, '학교', 'EDU');
CALL seed_recommend_mcc_mapping(8220, 8220, '대학', 'EDU');
CALL seed_recommend_mcc_mapping(8249, 8249, '학원', 'EDU');
CALL seed_recommend_mcc_mapping(8299, 8299, '교육 서비스', 'EDU');

CALL seed_recommend_mcc_mapping(4812, 4812, '통신장비', 'TELECOM');
CALL seed_recommend_mcc_mapping(4813, 4813, '통신 서비스', 'TELECOM');
CALL seed_recommend_mcc_mapping(4814, 4814, '통신사', 'TELECOM');
CALL seed_recommend_mcc_mapping(4816, 4816, '인터넷/통신', 'TELECOM');

CALL seed_recommend_mcc_mapping(4900, 4900, '공과금', 'UTILITY');
CALL seed_recommend_mcc_mapping(4911, 4911, '전기', 'UTILITY');
CALL seed_recommend_mcc_mapping(4941, 4941, '수도', 'UTILITY');
CALL seed_recommend_mcc_mapping(4961, 4961, '가스', 'UTILITY');

CALL seed_recommend_mcc_mapping(7011, 7011, '호텔', 'TRAVEL');
CALL seed_recommend_mcc_mapping(7012, 7012, '모텔/펜션', 'TRAVEL');

-- Final override for duplicated 4511.
CALL seed_recommend_mcc_mapping(4511, 4511, '항공사', 'AIRLINE');

CALL seed_recommend_mcc_mapping(6300, 6300, '보험사', 'INSURANCE');
CALL seed_recommend_mcc_mapping(6311, 6311, '생명보험', 'INSURANCE');
CALL seed_recommend_mcc_mapping(6321, 6321, '건강보험', 'INSURANCE');
CALL seed_recommend_mcc_mapping(6331, 6331, '손해보험', 'INSURANCE');
CALL seed_recommend_mcc_mapping(6399, 6399, '보험 서비스', 'INSURANCE');

COMMIT;

DROP PROCEDURE IF EXISTS seed_recommend_mcc_mapping;
