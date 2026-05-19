# Card Gorilla seed SQL generator

카드고릴라 크롤링 JSON을 ErumPay `card_db` 마스터 데이터용 MySQL seed SQL로 변환하는 독립 실행형 도구입니다.

이 도구는 DB에 직접 접속하지 않습니다. Spring Boot DTO, Entity, Repository, Service 코드도 만들지 않습니다.

## 입력

- `card_gorilla_cards.json`: 카드 상세와 혜택 원문
- `card_ids.json`: 카드 랭킹/상세 URL 보조 메타데이터

`rank`, `source_chart`, `source_month`는 현재 DB 컬럼이 없으므로 저장하지 않습니다.

## 출력

- `../../mysql/init/11-seed-card-gorilla-cards.sql`

SQL 파일은 다음 순서로 생성됩니다.

1. 헤더 주석
2. `SET NAMES utf8mb4;`
3. `USE card_db;`
4. `START TRANSACTION;`
5. `card_product`
6. `card_benefit`
7. `card_benefit_brand`
8. `card_benefit_tier`
9. `COMMIT;`
10. rollback 안내 주석

## 실행

dry-run은 SQL 파일을 만들지 않고 파싱 요약만 출력합니다.
`generated_*_count`는 DB affected rows가 아니라 생성된 SQL statement 수입니다.

```powershell
python generate_card_gorilla_seed_sql.py `
  --cards-json .\card_gorilla_cards.json `
  --ranks-json .\card_ids.json `
  --dry-run
```

SQL 파일 생성:

```powershell
python generate_card_gorilla_seed_sql.py `
  --cards-json .\card_gorilla_cards.json `
  --ranks-json .\card_ids.json
```

기본 output은 `erumpay-infra/mysql/init/11-seed-card-gorilla-cards.sql`입니다.
이 파일은 Docker MySQL init 디렉터리에 있으므로 새 `mysql_data` 볼륨 생성 시 schema 뒤에 자동 시딩됩니다.

자체 파서 검증:

```powershell
python generate_card_gorilla_seed_sql.py --self-test
```

pixi 환경을 사용하는 경우:

```powershell
pixi run dry-run-seed
pixi run generate-seed-sql
pixi run self-test
```

## 현재 DB 스키마 기준 저장 필드

### card_product

- `mock_bin`
- `card_company`
- `card_name`
- `card_type`
- `annual_fee`
- `image_url`
- `source_card_id`
- `source_url`
- `created_at`
- `updated_at`

### card_benefit

- `card_product_id`
- `service_category`
- `benefit_type`
- `min_amount`
- `time_start`
- `time_end`
- `day_condition`
- `benefit_desc`
- `priority`
- `created_at`
- `updated_at`

### card_benefit_brand

- `benefit_id`
- `brand_name`

주의: 현재 실행 대상 DB에 `card_benefit_brand` 테이블과 `UNIQUE(benefit_id, brand_name)` 제약이 실제로 있어야 합니다.

### card_benefit_tier

- `benefit_id`
- `min_prev_month_usage`
- `max_prev_month_usage`
- `rate`
- `flat_amount`
- `max_benefit_per_use`
- `daily_limit_count`
- `daily_limit_amount`
- `monthly_limit_count`
- `monthly_limit_amount`
- `yearly_limit_count`
- `yearly_limit_amount`
- `tier_desc`
- `created_at`
- `updated_at`

## 주요 정책

- 애매한 혜택은 잘못 추천하는 것보다 SKIP합니다.
- 브랜드 제한 혜택은 `card_benefit_brand`에 저장하고 카테고리 전체 혜택으로 확장하지 않습니다.
- 타사 간편결제 전용 혜택은 ErumPay 결제에서 받을 수 없으므로 SKIP합니다.
- `detail`의 "간편결제 제외" 문구만으로는 타사 페이 혜택으로 보지 않습니다.
- 선택형 안내 row는 SKIP하고, 실제 수치가 있는 선택형 후보는 모두 저장합니다.
- 현재 DB에는 사용자별 선택 옵션 저장 구조가 없으므로 추천 계산 시 실제 사용자가 선택하지 않은 혜택이 후보에 포함될 수 있습니다.
- 줄바꿈 또는 `/`, `·`로 나뉜 다중 혜택 row는 각 조각이 독립 혜택으로 파싱 가능한 경우에만 여러 `card_benefit` row로 분리합니다.
- 크롤링 JSON의 `tables`에 `구분/할인 대상` 같은 대상 표가 있으면 표 행 기준으로 혜택을 분리합니다.
- 표에 전월 이용금액대별 한도 표가 함께 있으면 `card_benefit_tier`를 실적 구간별로 생성합니다.
- 표 기반 split도 유의사항/해외/타사페이/선택형 안내 row에서는 수행하지 않습니다.
- `card_benefit.priority`는 추천 우선순위 의미를 보존하기 위해 모두 `0`으로 저장합니다. 원본 순번은 SQL 변수명/주석에만 사용합니다.
- 마일리지/포인트 단위형 적립은 `1마일/1포인트 = 1원` 기준으로 `rate`에 보수 환산합니다.
- 환산 원문은 `tier_desc`의 `[UNIT_REWARD ...]` 태그로 보존합니다.
- 브랜드 표기 변형은 seed 단계에서 가능한 범위만 대표명으로 정규화합니다. 예: `SSG COM`, `SSGCOM`, `SSG닷컴`은 `SSG.COM`으로 저장합니다.

## recommendation-service 키워드 매칭 규칙

`recommend_merchant_keyword_override`는 MCC가 부정확하거나 과도하게 넓은 경우 가맹점명을 기반으로 서비스 카테고리를 보정하는 테이블입니다.

recommendation-service는 이 테이블을 사용할 때 다음 규칙을 따라야 합니다.

1. 결제 가맹점명과 `keyword`를 동일한 방식으로 정규화합니다.
   - 공백 제거
   - 대소문자 통일
   - `.`/`-`/`_` 같은 구분 문자 통일 또는 제거
2. 정규화된 가맹점명에 포함되는 active keyword 후보를 모두 찾습니다.
3. `priority DESC`, 정규화된 keyword 길이 `DESC` 순으로 가장 구체적인 keyword 1개를 선택합니다.
4. keyword override가 없을 때만 MCC mapping을 사용합니다.

예:

- `이마트24 강남점`은 `이마트`보다 `이마트24`가 먼저 선택되어 `CVS`가 되어야 합니다.
- `쿠팡이츠`는 `쿠팡`보다 먼저 선택되어 `FOOD`가 되어야 합니다.
- `홈플러스 익스프레스`는 `홈플러스`보다 먼저 선택되어야 합니다.

## 검수해야 할 dry-run 항목

- `mapped_etc_category`
- `table_benefit_source_rows`
- `table_benefit_items`
- `table_limit_tier_groups`
- `possible_brand_review_items`
- `skipped_no_tier_value`
- `unit_reward_converted`
- `truncated_benefit_desc`
- `truncated_tier_desc`
- `mapped_other_card_company`
- `mock_bin_overflow`

## 재시딩 주의

`card_product`는 `source_card_id` 기준으로만 기존 row를 갱신합니다. `mock_bin`이 다른 `source_card_id`와 충돌하면 해당 카드의 insert를 막고 하위 혜택 SQL도 변수 guard로 실행되지 않게 합니다.

`card_benefit`에는 현재 원본 혜택을 식별할 자연키 컬럼이 없습니다. 그래서 benefit/tier/brand seed는 초기 적재 또는 정리 후 재적재를 전제로 한 append 성격입니다. 같은 SQL을 이미 실행한 DB에 다시 실행하면 `card_benefit` 중복 row가 생길 수 있으므로, 재크롤링이나 재시딩 전에는 기존 seed 데이터 정리 정책을 먼저 확인해야 합니다.

Docker init SQL은 MySQL 데이터 볼륨이 처음 생성될 때만 자동 실행됩니다. 이미 DB를 띄운 적 있으면 `docker compose down -v` 후 `docker compose up -d`해야 `11-seed-card-gorilla-cards.sql`이 자동 실행됩니다.
