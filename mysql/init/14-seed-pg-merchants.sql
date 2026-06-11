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
VALUES
    (101, '이룸카페 강남점', '123-45-67890', '이루미', '02-1234-5678', '서울특별시 강남구 테헤란로 123', '카페', '5811', 'dev-merchant-api-key-101', 'ACTIVE', NOW(), NULL, 1.50, 'dev-settlement-account-101', 'ACTIVE', NOW(), NULL, NULL, NOW()),
    (201, '스타벅스 강남역점', '201-10-00001', '김스타', '02-555-1001', '서울특별시 강남구 강남대로 396', '카페', '5814', 'dev-merchant-api-key-201', 'ACTIVE', NOW(), NULL, 1.50, 'dev-settlement-account-201', 'ACTIVE', NOW(), NULL, NULL, NOW()),
    (202, 'CU 역삼센터점', '201-10-00002', '박씨유', '02-555-1002', '서울특별시 강남구 테헤란로 152', '편의점', '5411', 'dev-merchant-api-key-202', 'ACTIVE', NOW(), NULL, 1.50, 'dev-settlement-account-202', 'ACTIVE', NOW(), NULL, NULL, NOW()),
    (203, 'GS25 선릉역점', '201-10-00003', '이선릉', '02-555-1003', '서울특별시 강남구 선릉로 428', '편의점', '5411', 'dev-merchant-api-key-203', 'ACTIVE', NOW(), NULL, 1.50, 'dev-settlement-account-203', 'ACTIVE', NOW(), NULL, NULL, NOW()),
    (204, '이마트24 삼성역점', '201-10-00004', '최삼성', '02-555-1004', '서울특별시 강남구 영동대로 513', '편의점', '5411', 'dev-merchant-api-key-204', 'ACTIVE', NOW(), NULL, 1.50, 'dev-settlement-account-204', 'ACTIVE', NOW(), NULL, NULL, NOW()),
    (205, '올리브영 홍대입구점', '201-10-00005', '정올리브', '02-555-1005', '서울특별시 마포구 양화로 160', '뷰티', '5977', 'dev-merchant-api-key-205', 'ACTIVE', NOW(), NULL, 1.50, 'dev-settlement-account-205', 'ACTIVE', NOW(), NULL, NULL, NOW()),

    (206, '이마트 용산점', '201-10-00006', '한용산', '02-555-1006', '서울특별시 용산구 한강대로 23길 55', '마트', '5411', 'dev-merchant-api-key-206', 'ACTIVE', NOW(), NULL, 1.50, 'dev-settlement-account-206', 'ACTIVE', NOW(), NULL, NULL, NOW()),
    (207, '홈플러스 합정점', '201-10-00007', '오합정', '02-555-1007', '서울특별시 마포구 양화로 45', '마트', '5411', 'dev-merchant-api-key-207', 'ACTIVE', NOW(), NULL, 1.50, 'dev-settlement-account-207', 'ACTIVE', NOW(), NULL, NULL, NOW()),
    (208, '롯데마트 잠실점', '201-10-00008', '송잠실', '02-555-1008', '서울특별시 송파구 올림픽로 240', '마트', '5411', 'dev-merchant-api-key-208', 'ACTIVE', NOW(), NULL, 1.50, 'dev-settlement-account-208', 'ACTIVE', NOW(), NULL, NULL, NOW()),
    (209, '롯데백화점 본점', '201-10-00009', '남본점', '02-555-1009', '서울특별시 중구 남대문로 81', '백화점', '5311', 'dev-merchant-api-key-209', 'ACTIVE', NOW(), NULL, 1.50, 'dev-settlement-account-209', 'ACTIVE', NOW(), NULL, NULL, NOW()),
    (210, '현대백화점 무역센터점', '201-10-00010', '강무역', '02-555-1010', '서울특별시 강남구 테헤란로 517', '백화점', '5311', 'dev-merchant-api-key-210', 'ACTIVE', NOW(), NULL, 1.50, 'dev-settlement-account-210', 'ACTIVE', NOW(), NULL, NULL, NOW()),

    (211, '쿠팡 잠실물류센터', '201-10-00011', '문쿠팡', '02-555-1011', '서울특별시 송파구 송파대로 570', '온라인쇼핑', '5399', 'dev-merchant-api-key-211', 'ACTIVE', NOW(), NULL, 1.50, 'dev-settlement-account-211', 'ACTIVE', NOW(), NULL, NULL, NOW()),
    (212, '배달의 민족 강남지점', '201-10-00012', '배민수', '02-555-1012', '서울특별시 강남구 논현로 508', '음식', '5812', 'dev-merchant-api-key-212', 'ACTIVE', NOW(), NULL, 1.50, 'dev-settlement-account-212', 'ACTIVE', NOW(), NULL, NULL, NOW()),
    (213, '파리바게뜨 교대역점', '201-10-00013', '윤교대', '02-555-1013', '서울특별시 서초구 서초대로 302', '음식', '5812', 'dev-merchant-api-key-213', 'ACTIVE', NOW(), NULL, 1.50, 'dev-settlement-account-213', 'ACTIVE', NOW(), NULL, NULL, NOW()),
    (214, '투썸플레이스 성수점', '201-10-00014', '성투썸', '02-555-1014', '서울특별시 성동구 성수이로 87', '카페', '5814', 'dev-merchant-api-key-214', 'ACTIVE', NOW(), NULL, 1.50, 'dev-settlement-account-214', 'ACTIVE', NOW(), NULL, NULL, NOW()),
    (215, '메가커피 신촌점', '201-10-00015', '신메가', '02-555-1015', '서울특별시 서대문구 연세로 12', '카페', '5814', 'dev-merchant-api-key-215', 'ACTIVE', NOW(), NULL, 1.50, 'dev-settlement-account-215', 'ACTIVE', NOW(), NULL, NULL, NOW()),

    (216, 'CGV 용산아이파크몰', '201-10-00016', '장용산', '02-555-1016', '서울특별시 용산구 한강대로23길 55', '영화', '7832', 'dev-merchant-api-key-216', 'ACTIVE', NOW(), NULL, 1.50, 'dev-settlement-account-216', 'ACTIVE', NOW(), NULL, NULL, NOW()),
    (217, '롯데시네마 월드타워점', '201-10-00017', '석월드', '02-555-1017', '서울특별시 송파구 올림픽로 300', '영화', '7832', 'dev-merchant-api-key-217', 'ACTIVE', NOW(), NULL, 1.50, 'dev-settlement-account-217', 'ACTIVE', NOW(), NULL, NULL, NOW()),
    (218, 'SKT 강남대리점', '201-10-00018', '최에스케이', '02-555-1018', '서울특별시 강남구 강남대로 408', '통신', '4814', 'dev-merchant-api-key-218', 'ACTIVE', NOW(), NULL, 1.50, 'dev-settlement-account-218', 'ACTIVE', NOW(), NULL, NULL, NOW()),
    (219, 'GS칼텍스 서초주유소', '201-10-00019', '서칼텍스', '02-555-1019', '서울특별시 서초구 반포대로 222', '주유', '5541', 'dev-merchant-api-key-219', 'ACTIVE', NOW(), NULL, 1.50, 'dev-settlement-account-219', 'ACTIVE', NOW(), NULL, NULL, NOW()),
    (220, '교보문고 광화문점', '201-10-00020', '광교보', '02-555-1020', '서울특별시 종로구 종로 1', '도서', '5942', 'dev-merchant-api-key-220', 'ACTIVE', NOW(), NULL, 1.50, 'dev-settlement-account-220', 'ACTIVE', NOW(), NULL, NULL, NOW())
    ON DUPLICATE KEY UPDATE
                         merchant_name = VALUES(merchant_name),
                         owner_name = VALUES(owner_name),
                         contact_phone = VALUES(contact_phone),
                         business_address = VALUES(business_address),
                         category_name = VALUES(category_name),
                         mcc_code = VALUES(mcc_code),
                         api_key = VALUES(api_key),
                         api_key_status = VALUES(api_key_status),
                         fee_rate = VALUES(fee_rate),
                         settlement_account = VALUES(settlement_account),
                         status = VALUES(status),
                         updated_at = NOW(),
                         suspend_reason = NULL,
                         deleted_at = NULL;
