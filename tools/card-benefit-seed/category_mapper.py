from __future__ import annotations

import re
from collections import defaultdict
from typing import Iterable


CARD_COMPANY_PREFIXES = {
    "삼성카드": "80",
    "신한카드": "81",
    "현대카드": "82",
    "KB국민카드": "83",
    "KB국민": "83",
    "롯데카드": "84",
    "우리카드": "85",
    "하나카드": "86",
    "NH농협카드": "87",
    "NH농협": "87",
    "IBK기업은행": "88",
    "IBK기업카드": "88",
}

OTHER_CARD_COMPANY_PREFIX = "89"

THIRD_PARTY_PAY_KEYWORDS = {
    "네이버페이",
    "카카오페이",
    "삼성페이",
    "KB Pay",
    "KB페이",
    "NH pay",
    "NH페이",
    "하나페이",
    "PAYCO",
    "페이코",
    "토스페이",
    "SSGPAY",
    "SSG PAY",
    "L.PAY",
    "엘페이",
    "Apple Pay",
    "애플페이",
}

BRAND_SEED = {
    "스타벅스",
    "폴바셋",
    "투썸플레이스",
    "커피빈",
    "이디야",
    "메가커피",
    "컴포즈커피",
    "할리스",
    "엔제리너스",
    "매머드커피",
    "빽다방",
    "배달의민족",
    "배달의 민족",
    "요기요",
    "쿠팡이츠",
    "땡겨요",
    "쿠팡",
    "네이버플러스 스토어",
    "네이버플러스스토어",
    "마켓컬리",
    "컬리",
    "오아시스마켓",
    "삼성카드 쇼핑",
    "GS25",
    "CU",
    "세븐일레븐",
    "이마트24",
    "이마트",
    "이마트 에브리데이",
    "메가마트",
    "Y_MART",
    "영암마트",
    "트레이더스",
    "트레이더스 홀세일 클럽",
    "홈플러스",
    "홈플러스 익스프레스",
    "롯데마트",
    "롯데마트 맥스",
    "롯데슈퍼",
    "GS 수퍼마켓",
    "GS수퍼마켓",
    "코스트코",
    "올리브영",
    "LOHB's",
    "롭스",
    "시코르",
    "다이소",
    "CGV",
    "롯데시네마",
    "메가박스",
    "넷플릭스",
    "유튜브",
    "디즈니플러스",
    "디즈니+",
    "티빙",
    "웨이브",
    "왓챠",
    "멜론",
    "지니뮤직",
    "쿠팡 와우 멤버십",
    "네이버플러스 멤버십",
    "GS칼텍스",
    "SK에너지",
    "S-OIL",
    "현대오일뱅크",
    "HD현대오일뱅크",
    "11번가",
    "G마켓",
    "옥션",
    "SSG.COM",
    "SSG COM",
    "SSGCOM",
    "SSG닷컴",
    "신세계백화점",
    "롯데백화점",
    "현대백화점",
    "롯데프리미엄아울렛",
    "현대프리미엄아울렛",
    "신세계사이먼",
    "스타필드",
    "에버랜드",
    "롯데월드",
    "아웃백",
    "VIPS",
    "파리바게뜨",
    "뚜레쥬르",
    "NOL 티켓",
    "알라딘",
    "와인앤모어",
    "이케아",
    "이투스",
    "메가스터디교육",
    "메가스터디",
    "엠베스트",
    "엘리하이",
    "대성마이맥",
    "천재교과서",
    "밀크T",
    "웅진씽크빅",
    "교원",
    "대교",
    "한솔교육",
    "SK텔레콤",
    "SKT",
    "KT",
    "LG U+",
    "LGU+",
}

CATEGORY_WORDS = {
    "카페",
    "커피",
    "디저트",
    "베이커리",
    "패밀리레스토랑",
    "패스트푸드",
    "음식점",
    "일반음식점",
    "배달앱",
    "푸드",
    "식음료",
    "점심",
    "편의점",
    "주유",
    "주유소",
    "충전소",
    "자동차",
    "정비",
    "하이패스",
    "렌터카",
    "대중교통",
    "교통",
    "지하철",
    "버스",
    "기차",
    "고속버스",
    "택시",
    "온라인쇼핑",
    "온라인쇼핑몰",
    "쇼핑",
    "홈쇼핑",
    "리셀쇼핑",
    "백화점",
    "면세점",
    "소셜커머스",
    "해외직구",
    "아웃렛",
    "생활잡화",
    "잡화",
    "대형마트",
    "대형 할인점",
    "창고형 할인매장",
    "슈퍼마켓",
    "마트",
    "할인점",
    "통신",
    "디지털구독",
    "디지털콘텐츠",
    "OTT",
    "스트리밍",
    "음원",
    "멤버십",
    "인앱 결제",
    "APP",
    "영화",
    "공연",
    "전시",
    "게임",
    "도서",
    "서점",
    "테마파크",
    "놀이공원",
    "골프",
    "레저",
    "공항",
    "여행",
    "호텔",
    "리조트",
    "숙박",
    "여행사",
    "항공",
    "항공권",
    "병원",
    "의료",
    "약국",
    "미용실",
    "헤어",
    "뷰티",
    "드럭스토어",
    "스포츠",
    "피트니스",
    "헬스",
    "교육",
    "학원",
    "학습지",
    "공과금",
    "아파트관리비",
    "도시가스",
    "전기료",
    "렌탈",
    "보험",
}

CATEGORY_MAPPINGS = [
    ("ALL", ("모든가맹점", "모든 가맹점", "전가맹점", "전 가맹점", "전체가맹점", "전체 가맹점", "국내가맹점", "국내 가맹점", "국내외가맹점", "국내외 가맹점")),
    ("CAFE", ("카페", "커피", "디저트")),
    ("FOOD", ("베이커리", "패밀리레스토랑", "패스트푸드", "음식점", "일반음식점", "배달앱", "푸드", "식음료", "점심")),
    ("CVS", ("편의점",)),
    ("AUTO", ("주유", "주유소", "충전소", "자동차", "정비", "하이패스")),
    ("TRAVEL", ("렌터카",)),
    ("TRANSIT", ("대중교통", "교통", "지하철", "버스", "기차", "고속버스")),
    ("TAXI", ("택시",)),
    ("SHOPPING", ("온라인쇼핑몰", "온라인쇼핑", "쇼핑", "홈쇼핑", "리셀쇼핑", "백화점", "면세점", "소셜커머스", "해외직구", "아웃렛", "생활잡화", "잡화")),
    ("GROCERY", ("대형마트", "대형 할인점", "창고형 할인매장", "슈퍼마켓", "마트", "할인점")),
    ("TELECOM", ("통신", "SK텔레콤", "SKT", "KT", "LG U+", "LGU+")),
    ("ETC", ("디지털구독", "디지털콘텐츠", "OTT", "스트리밍", "음원", "멤버십", "인앱 결제", "APP", "보틀숍")),
    ("LEISURE", ("영화", "공연", "전시", "게임", "도서", "서점", "테마파크", "놀이공원", "골프", "레저")),
    ("TRAVEL", ("공항", "여행", "호텔", "리조트", "숙박", "여행사")),
    ("AIRLINE", ("대한항공", "항공", "항공권", "항공마일리지")),
    ("HEALTH", ("병원/약국", "병원", "의료")),
    ("PHARMACY", ("약국",)),
    ("BEAUTY", ("미용실", "헤어", "뷰티", "드럭스토어", "올리브영")),
    ("FITNESS", ("스포츠", "피트니스", "헬스")),
    ("EDU", ("교육/육아", "교육", "학원", "학습지", "인터넷강의")),
    ("UTILITY", ("공과금", "아파트관리비", "도시가스", "전기료", "렌탈")),
    ("INSURANCE", ("보험사", "보험")),
    ("ETC", ("멤버십포인트", "애완동물", "비즈니스", "혜택 프로모션")),
]

REVIEW_BRAND_SETS = (
    {"CGV", "롯데시네마", "메가박스"},
    {"GS25", "CU", "세븐일레븐", "이마트24"},
)

SHORT_BRAND_ALLOWLIST = {"CU", "KT", "쿠팡", "컬리", "옥션", "멜론", "티빙", "왓챠", "교원", "대교"}


def compact(text: str | None) -> str:
    return re.sub(r"\s+", "", text or "")


def canonical_brand_name(value: str | None) -> str:
    cleaned = (value or "").strip()
    normalized = re.sub(r"[\s._-]+", "", cleaned).lower()
    if normalized in {"ssgcom", "ssg닷컴"}:
        return "SSG.COM"
    return cleaned


def normalized_contains(text: str, keyword: str) -> bool:
    return compact(keyword).lower() in compact(text).lower()


def normalize_card_company(corp: str | None) -> str:
    return compact(corp)


def card_company_prefix(corp: str | None) -> tuple[str, bool]:
    normalized = normalize_card_company(corp)
    for company, prefix in CARD_COMPANY_PREFIXES.items():
        if normalized == compact(company):
            return prefix, False
    return OTHER_CARD_COMPANY_PREFIX, True


def map_service_category(main_title: str | None, sub_title: str | None, detail: str | None = None) -> str:
    primary_text = "\n".join(part for part in [main_title or "", sub_title or ""] if part)

    for category, keywords in CATEGORY_MAPPINGS:
        if any(normalized_contains(primary_text, keyword) for keyword in keywords):
            return category

    if detail:
        for category, keywords in CATEGORY_MAPPINGS:
            if any(normalized_contains(detail, keyword) for keyword in keywords):
                return category

    return "ETC"


def ordered_unique(values: Iterable[str]) -> list[str]:
    seen: set[str] = set()
    result: list[str] = []
    for value in values:
        cleaned = canonical_brand_name(value)
        if not cleaned:
            continue
        key = compact(cleaned).lower()
        if key in seen:
            continue
        seen.add(key)
        result.append(cleaned)
    return result


def is_third_party_pay_keyword(text: str) -> bool:
    return any(normalized_contains(text, keyword) for keyword in THIRD_PARTY_PAY_KEYWORDS)


def is_category_word(value: str) -> bool:
    return any(compact(value).lower() == compact(keyword).lower() for keyword in CATEGORY_WORDS)


def is_third_party_pay_name(value: str) -> bool:
    return any(compact(value).lower() == compact(keyword).lower() for keyword in THIRD_PARTY_PAY_KEYWORDS)


def extract_brand_names(
    main_title: str | None,
    sub_title: str | None,
    detail: str | None = None,
    brand_candidates: Iterable[str] | None = None,
) -> list[str]:
    candidates = set(BRAND_SEED)
    if brand_candidates:
        candidates.update(brand_candidates)

    primary_text = "\n".join(part for part in [main_title or "", sub_title or ""] if part)
    matches = []
    for brand in sorted(candidates, key=lambda value: (-len(value), value)):
        if len(compact(brand)) <= 2 and brand not in SHORT_BRAND_ALLOWLIST:
            continue
        if compact(brand).upper() == "SK":
            continue
        if is_category_word(brand) or is_third_party_pay_name(brand):
            continue
        if normalized_contains(primary_text, brand):
            matches.append(brand)

    unique_matches = ordered_unique(matches)
    compact_matches = {brand: compact(brand).lower() for brand in unique_matches}
    return [
        brand
        for brand in unique_matches
        if not any(
            compact_matches[brand] != other_compact and compact_matches[brand] in other_compact
            for other, other_compact in compact_matches.items()
        )
    ]


def extract_detail_only_brand_candidates(
    main_title: str | None,
    sub_title: str | None,
    detail: str | None,
    brand_candidates: Iterable[str] | None = None,
) -> list[str]:
    primary = "\n".join(part for part in [main_title or "", sub_title or ""] if part)
    candidates = set(BRAND_SEED)
    if brand_candidates:
        candidates.update(brand_candidates)

    matches = []
    for brand in sorted(candidates, key=lambda value: (-len(value), value)):
        if normalized_contains(primary, brand):
            continue
        if detail and normalized_contains(detail, brand):
            matches.append(brand)
    return ordered_unique(matches)


def is_brand_restricted(main_title: str | None, sub_title: str | None, detail: str | None = None) -> bool:
    text = "\n".join(part for part in [main_title or "", sub_title or ""] if part)
    if extract_brand_names(main_title, sub_title, detail):
        return True
    restriction_hints = ("특정", "지정", "제휴", "대상 브랜드", "대상점", "대상 가맹점")
    return any(normalized_contains(text, hint) for hint in restriction_hints)


def is_review_brand_group(brand_names: Iterable[str]) -> bool:
    names = set(brand_names)
    return any(len(names & group) >= 2 for group in REVIEW_BRAND_SETS)


def extract_brand_candidates_from_cards(cards: list[dict]) -> list[str]:
    counts: dict[str, int] = defaultdict(int)
    for card in cards:
        for benefit in card.get("benefits") or []:
            text = "\n".join(
                part
                for part in [
                    benefit.get("main_title") or "",
                    benefit.get("sub_title") or "",
                ]
                if part
            )
            for table in benefit.get("tables") or []:
                table_text = "\n".join(
                    [
                        table.get("context") or "",
                        " ".join(table.get("headers") or []),
                        "\n".join(" ".join(row) for row in table.get("rows") or []),
                    ]
                )
                if table_text:
                    text = "\n".join([text, table_text])
            for brand in BRAND_SEED:
                if normalized_contains(text, brand):
                    counts[canonical_brand_name(brand)] += 1

    return [brand for brand, _ in sorted(counts.items(), key=lambda item: (-item[1], item[0]))]
