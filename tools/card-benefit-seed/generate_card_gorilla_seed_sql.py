from __future__ import annotations

import argparse
import json
import re
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path
from typing import Any

from category_mapper import (
    card_company_prefix,
    extract_brand_candidates_from_cards,
    extract_brand_names,
    extract_detail_only_brand_candidates,
    is_brand_restricted,
    is_review_brand_group,
    is_third_party_pay_keyword,
    map_service_category,
)
from parsers import (
    build_rank_map,
    infer_benefit_type,
    load_json,
    normalize_money,
    normalize_spaces,
    parse_annual_fee,
    parse_day_condition,
    parse_flat_amount,
    parse_min_amount,
    parse_rate,
    parse_time_condition,
    parse_tiers,
    parse_unit_reward_rate,
    split_representative_line,
    sql_literal,
    strip_exclusion_sections,
    truncate_text,
)


BENEFIT_DESC_MAX_LENGTH = 500
TIER_DESC_MAX_LENGTH = 500
TOOL_DIR = Path(__file__).resolve().parent
INFRA_ROOT = TOOL_DIR.parent.parent
DEFAULT_OUTPUT_PATH = INFRA_ROOT / "mysql" / "init" / "11-seed-card-gorilla-cards.sql"

SKIP_COUNTERS = {
    "NOTICE": "skipped_notices",
    "OVERSEAS": "skipped_overseas",
    "THIRD_PARTY_PAY": "skipped_third_party_pay",
    "PREMIUM_OR_VOUCHER": "skipped_premium_or_voucher",
    "NON_PAYMENT_BENEFIT": "skipped_non_payment_benefit",
    "SELECTABLE_NOTICE_ONLY": "skipped_selectable_notice_only",
    "UNSUPPORTED_TYPE": "skipped_unsupported_type",
    "BRAND_WITHOUT_KEYWORD": "skipped_brand_restricted_without_keyword",
    "NO_TIER_VALUE": "skipped_no_tier_value",
    "INVALID_RATE": "skipped_invalid_rate",
    "UNIT_REWARD_TOO_SMALL": "skipped_unit_reward_too_small",
}


def _compact(text: str | None) -> str:
    return re.sub(r"\s+", "", text or "")


def _classification_text(main_title: str | None, sub_title: str | None) -> str:
    return "\n".join(part for part in [main_title or "", sub_title or ""] if part)


def is_notice(main_title: str | None, sub_title: str | None) -> bool:
    text = _classification_text(main_title, sub_title)
    return main_title in {"유의사항", "꼭 확인하세요!", "꼭 확인하세요"} or "유의사항" in text


def is_overseas(main_title: str | None, sub_title: str | None) -> bool:
    main = _compact(main_title)
    sub = _compact(sub_title)
    if main in {"해외", "해외이용"}:
        return True
    if main.startswith("해외") and "국내외" not in main:
        return True
    return sub.startswith("해외") and "국내외" not in sub


def is_third_party_pay_benefit(main_title: str | None, sub_title: str | None, detail: str | None = None) -> bool:
    main_sub = _classification_text(main_title, sub_title)
    compact = _compact(main_sub)
    if not compact:
        return False
    if "제외" in compact and not (main_title and "간편결제" in main_title):
        return False
    if "간편결제" in compact:
        return True
    if is_third_party_pay_keyword(main_sub):
        return True
    return bool(re.search(r"(?:\d+대\s*)?PAY결제시|페이결제시|Pay결제시", compact, re.IGNORECASE))


def is_premium_or_voucher(main_title: str | None, sub_title: str | None) -> bool:
    text = _classification_text(main_title, sub_title)
    compact = _compact(text)
    if "프리미엄아울렛" in compact:
        return False
    return any(keyword in compact for keyword in ("바우처", "공항라운지", "공항라운지/PP", "발렛파킹", "프리미엄서비스", "유튜브프리미엄"))


def is_non_payment_benefit(main_title: str | None, sub_title: str | None) -> bool:
    text = _classification_text(main_title, sub_title)
    return any(keyword in text for keyword in ("수수료우대", "무이자할부", "환율우대", "금융", "은행사"))


def is_selectable_notice_only(main_title: str | None, sub_title: str | None, detail: str | None = None) -> bool:
    text = _classification_text(main_title, sub_title)
    compact = _compact(text)
    if "선택옵션에따른" in compact and ("택1" in compact or "선택" in compact):
        return True
    if "패키지선택" in compact:
        return True
    if "선택형" in compact and "선택" in compact and not (parse_rate(text) or parse_flat_amount(text) or parse_unit_reward_rate(text)):
        return True
    if "카드플레이트선택" in compact:
        return True
    if "선택가능" in compact and not (parse_rate(text) or parse_flat_amount(text) or parse_unit_reward_rate(text)):
        return True
    return False


def _skip_sql_comment(card: dict, order: Any, reason: str, benefit: dict) -> str:
    title = normalize_spaces(benefit.get("main_title") or benefit.get("sub_title") or "")
    return f"-- SKIP benefit: source_card_id={card.get('card_id')}, order={order}, reason={reason}, title={title}"


def _var_suffix(source_card_id: Any, benefit_order: int | None = None) -> str:
    suffix = re.sub(r"[^0-9A-Za-z_]", "_", str(source_card_id))
    if benefit_order is not None:
        suffix = f"{suffix}_{benefit_order}"
    return suffix


def _card_product_var(source_card_id: Any) -> str:
    return f"@card_product_id_{_var_suffix(source_card_id)}"


def _benefit_var(source_card_id: Any, benefit_order: Any) -> str:
    return f"@benefit_id_{_var_suffix(source_card_id, benefit_order)}"


def generate_mock_bin(card_company: str, card_type: str, sequence: int) -> str:
    prefix, _ = card_company_prefix(card_company)
    return f"{prefix}{sequence:04d}"


def build_mock_bin_map(cards: list[dict]) -> tuple[dict[str, str], list[str], list[str]]:
    counters: dict[tuple[str, str], int] = defaultdict(int)
    mock_bins: dict[str, str] = {}
    mapped_other: list[str] = []
    overflow: list[str] = []

    sorted_cards = sorted(
        cards,
        key=lambda card: (
            str(card.get("card_type") or ""),
            str(card.get("corp") or ""),
            int(card.get("card_id") or 0),
        ),
    )

    for card in sorted_cards:
        card_type = str(card.get("card_type") or "").upper()
        corp = str(card.get("corp") or "")
        prefix, is_other = card_company_prefix(corp)
        if is_other:
            mapped_other.append(corp)

        key = (prefix, card_type)
        base = 500 if card_type == "CHECK" else 0
        sequence = base + counters[key]
        counters[key] += 1

        if (card_type == "CHECK" and sequence > 999) or (card_type != "CHECK" and sequence > 499):
            overflow.append(f"{corp}:{card_type}:{card.get('card_id')}")
            continue

        mock_bins[str(card.get("card_id"))] = generate_mock_bin(corp, card_type, sequence)

    return mock_bins, sorted(set(mapped_other)), overflow


def generate_card_product_sql(card: dict, rank_meta: dict | None, mock_bin: str) -> str:
    source_card_id = str(card.get("card_id"))
    source_url = card.get("url") or (rank_meta or {}).get("detail_url")
    insert_values = [
        sql_literal(mock_bin),
        sql_literal(card.get("corp") or ""),
        sql_literal(card.get("name") or ""),
        sql_literal(card.get("card_type") or ""),
        sql_literal(parse_annual_fee(card.get("fee"))),
        sql_literal(card.get("image_url") or None),
        sql_literal(source_card_id),
        sql_literal(source_url or None),
        "NOW()",
        "NOW()",
    ]
    product_var = _card_product_var(source_card_id)

    return "\n".join(
        [
            f"-- card_product: source_card_id={source_card_id}, name={normalize_spaces(card.get('name'))}",
            "-- mock_bin collision guard: insert only when mock_bin is unused or already belongs to the same source_card_id.",
            "INSERT INTO card_product (",
            "  mock_bin, card_company, card_name, card_type, annual_fee, image_url, source_card_id, source_url, created_at, updated_at",
            ")",
            f"SELECT {', '.join(insert_values)}",
            "FROM DUAL",
            "WHERE NOT EXISTS (",
            "    SELECT 1",
            "    FROM card_product",
            f"    WHERE source_card_id = {sql_literal(source_card_id)}",
            "  )",
            "  AND NOT EXISTS (",
            "    SELECT 1",
            "    FROM card_product",
            f"    WHERE mock_bin = {sql_literal(mock_bin)}",
            f"      AND source_card_id <> {sql_literal(source_card_id)}",
            "  );",
            "UPDATE card_product",
            "SET card_company = " + sql_literal(card.get("corp") or "") + ",",
            "    card_name = " + sql_literal(card.get("name") or "") + ",",
            "    card_type = " + sql_literal(card.get("card_type") or "") + ",",
            "    annual_fee = " + sql_literal(parse_annual_fee(card.get("fee"))) + ",",
            "    image_url = " + sql_literal(card.get("image_url") or None) + ",",
            "    source_url = " + sql_literal(source_url or None) + ",",
            "    updated_at = NOW()",
            f"WHERE source_card_id = {sql_literal(source_card_id)};",
            f"SET {product_var} = (",
            "  SELECT card_product_id",
            "  FROM card_product",
            f"  WHERE source_card_id = {sql_literal(source_card_id)}",
            "  LIMIT 1",
            ");",
        ]
    )


def generate_card_benefit_sql(card: dict, benefit: dict, benefit_order: Any, tiers: list[dict], benefit_desc: str | None, service_category: str, benefit_type: str, min_amount: int | None, time_start: str | None, time_end: str | None, day_condition: str) -> str:
    source_card_id = str(card.get("card_id"))
    product_var = _card_product_var(source_card_id)
    benefit_var = _benefit_var(source_card_id, benefit_order)
    values = [
        product_var,
        sql_literal(service_category),
        sql_literal(benefit_type),
        sql_literal(min_amount),
        sql_literal(time_start),
        sql_literal(time_end),
        sql_literal(day_condition),
        sql_literal(benefit_desc),
        "0",
        "NOW()",
        "NOW()",
    ]
    predicates = [
        f"cb.card_product_id = {product_var}",
        f"cb.service_category = {sql_literal(service_category)}",
        f"cb.benefit_type = {sql_literal(benefit_type)}",
        f"cb.min_amount <=> {sql_literal(min_amount)}",
        f"cb.time_start <=> {sql_literal(time_start)}",
        f"cb.time_end <=> {sql_literal(time_end)}",
        f"cb.day_condition = {sql_literal(day_condition)}",
        f"cb.benefit_desc <=> {sql_literal(benefit_desc)}",
        "cb.priority = 0",
    ]
    predicate_sql = "\n      AND ".join(predicates)
    return "\n".join(
        [
            f"-- card_benefit: source_card_id={source_card_id}, order={benefit_order}, category={service_category}, type={benefit_type}, priority=0",
            f"SET {benefit_var} = NULL;",
            "INSERT INTO card_benefit (",
            "  card_product_id, service_category, benefit_type, min_amount, time_start, time_end, day_condition, benefit_desc, priority, created_at, updated_at",
            ")",
            f"SELECT {', '.join(values)}",
            "FROM DUAL",
            f"WHERE {product_var} IS NOT NULL",
            "  AND NOT EXISTS (",
            "    SELECT 1",
            "    FROM card_benefit cb",
            f"    WHERE {predicate_sql}",
            "  );",
            f"SET {benefit_var} = (",
            "  SELECT cb.benefit_id",
            "  FROM card_benefit cb",
            f"  WHERE {predicate_sql}",
            "  ORDER BY cb.benefit_id",
            "  LIMIT 1",
            ");",
        ]
    )


def generate_card_benefit_brand_sql(card: dict, benefit: dict, benefit_order: Any, brand_names: list[str]) -> list[str]:
    source_card_id = str(card.get("card_id"))
    benefit_var = _benefit_var(source_card_id, benefit_order)
    statements = []
    for brand_name in brand_names:
        statements.append(
            "\n".join(
                [
                    f"-- card_benefit_brand: source_card_id={source_card_id}, order={benefit_order}, brand={brand_name}",
                    "INSERT INTO card_benefit_brand (benefit_id, brand_name)",
                    f"SELECT {benefit_var}, {sql_literal(brand_name)}",
                    "FROM DUAL",
                    f"WHERE {benefit_var} IS NOT NULL",
                    "  AND NOT EXISTS (",
                    "    SELECT 1",
                    "    FROM card_benefit_brand",
                    f"    WHERE benefit_id = {benefit_var}",
                    f"      AND brand_name = {sql_literal(brand_name)}",
                    "  );",
                ]
            )
        )
    return statements


def generate_card_benefit_tier_sql(card: dict, benefit: dict, benefit_order: Any, tier: dict) -> str:
    source_card_id = str(card.get("card_id"))
    benefit_var = _benefit_var(source_card_id, benefit_order)
    values = [
        benefit_var,
        sql_literal(tier.get("min_prev_month_usage") if tier.get("min_prev_month_usage") is not None else 0),
        sql_literal(tier.get("max_prev_month_usage")),
        sql_literal(tier.get("rate")),
        sql_literal(tier.get("flat_amount")),
        sql_literal(tier.get("max_benefit_per_use")),
        sql_literal(tier.get("daily_limit_count")),
        sql_literal(tier.get("daily_limit_amount")),
        sql_literal(tier.get("monthly_limit_count")),
        sql_literal(tier.get("monthly_limit_amount")),
        sql_literal(tier.get("yearly_limit_count")),
        sql_literal(tier.get("yearly_limit_amount")),
        sql_literal(tier.get("tier_desc")),
        "NOW()",
        "NOW()",
    ]
    min_usage = tier.get("min_prev_month_usage") if tier.get("min_prev_month_usage") is not None else 0
    return "\n".join(
        [
            f"-- card_benefit_tier: source_card_id={source_card_id}, order={benefit_order}, min_prev_month_usage={min_usage}",
            "INSERT INTO card_benefit_tier (",
            "  benefit_id, min_prev_month_usage, max_prev_month_usage, rate, flat_amount, max_benefit_per_use,",
            "  daily_limit_count, daily_limit_amount, monthly_limit_count, monthly_limit_amount,",
            "  yearly_limit_count, yearly_limit_amount, tier_desc, created_at, updated_at",
            ")",
            f"SELECT {', '.join(values)}",
            "FROM DUAL",
            f"WHERE {benefit_var} IS NOT NULL",
            "  AND NOT EXISTS (",
            "    SELECT 1",
            "    FROM card_benefit_tier",
            f"    WHERE benefit_id = {benefit_var}",
            f"      AND min_prev_month_usage = {sql_literal(min_usage)}",
            "  );",
        ]
    )


def _benefit_desc(sub_title: str | None, detail: str | None) -> str:
    parts = [part.strip() for part in [sub_title or "", detail or ""] if part and part.strip()]
    return "\n".join(parts)


VALUE_WITH_SUFFIX_RE = re.compile(
    r"((?:리터당|L당)\s*\d[\d,]*(?:\.\d+)?\s*원|\d+(?:\.\d+)?\s*%|\d[\d,]*(?:\.\d+)?\s*(?:만원|천원|원))"
    r"\s*(청구할인|결제일\s*할인|결제일할인|할인|캐시백|(?:NH)?포인트\s*적립|마일리지\s*적립|적립)?"
)

SPLIT_CATEGORY_ALIASES = {
    "배달": "FOOD",
    "배달앱": "FOOD",
    "Dining": "FOOD",
    "커피": "CAFE",
    "커피전문점": "CAFE",
    "음료전문점": "CAFE",
    "영화관": "LEISURE",
    "영화": "LEISURE",
    "의료": "HEALTH",
    "온라인쇼핑몰": "SHOPPING",
    "온라인쇼핑": "SHOPPING",
    "온라인몰": "SHOPPING",
    "홈쇼핑": "SHOPPING",
    "Shopping": "SHOPPING",
    "백화점": "SHOPPING",
    "프리미엄 아울렛": "SHOPPING",
    "생활잡화": "SHOPPING",
    "잡화": "SHOPPING",
    "대형 할인점": "GROCERY",
    "창고형 할인매장": "GROCERY",
    "슈퍼마켓": "GROCERY",
    "할인점": "GROCERY",
    "마트": "GROCERY",
    "디지털콘텐츠": "ETC",
    "멤버십": "ETC",
    "인앱 결제": "ETC",
    "보틀숍": "ETC",
    "OTT": "ETC",
    "Entertainment": "LEISURE",
    "운동": "FITNESS",
    "학원": "EDU",
    "인터넷강의": "EDU",
    "학습지": "EDU",
    "보험료": "INSURANCE",
    "Travel": "TRAVEL",
    "HOTEL": "TRAVEL",
    "AUTO": "AUTO",
}

SHARED_LIMIT_RE = re.compile(
    r"통합|월\s*(?:할인|적립|캐시백|혜택)?\s*한도|월\s*최대|월간\s*통합|서비스\s*통합|영역\s*통합"
)


def _has_benefit_value(text: str) -> bool:
    if parse_rate(text) is not None or parse_flat_amount(text) is not None or parse_unit_reward_rate(text) is not None:
        return True
    if _looks_condition_line(text):
        return False
    return bool(re.search(r"\d[\d,]*(?:\.\d+)?\s*(?:만\s*\d*\s*천\s*)?원", text))


def _is_benefit_line(text: str, inherited_type: str | None = None) -> bool:
    own_type = infer_benefit_type("", text, "")
    if own_type is None and inherited_type is not None and (_looks_condition_line(text) or _looks_meta_line(text)):
        return False
    has_type = own_type is not None or inherited_type is not None
    return has_type and _has_benefit_value(text)


def _looks_condition_line(text: str) -> bool:
    compact = _compact(text)
    return any(
        keyword in compact
        for keyword in (
            "전월",
            "이용금액",
            "실적",
            "이상시",
            "제공",
            "한도",
            "월",
            "연",
            "일",
            "조건",
            "발급",
            "기간",
            "제외",
            "대상",
            "유의",
        )
    )


def _is_condition_line(text: str) -> bool:
    if _is_benefit_line(text):
        return False
    return _looks_condition_line(text)


def _looks_meta_line(text: str) -> bool:
    compact = _compact(text)
    return any(
        keyword in compact
        for keyword in (
            "선택옵션",
            "디자인",
            "플레이트",
            "쿠폰서비스",
            "제휴항공사",
            "브랜드",
            "택1",
            "소개합니다",
            "기부",
        )
    )


def _is_meta_line(text: str) -> bool:
    if _is_benefit_line(text):
        return False
    return _looks_meta_line(text)


def _split_segments(line: str, inherited_type: str | None) -> list[str]:
    raw_segments = [segment.strip(" ,") for segment in re.split(r"\s*/\s*|\s+·\s+", line) if segment.strip(" ,")]
    if len(raw_segments) < 2:
        return [line]

    benefit_segments = [segment for segment in raw_segments if _is_benefit_line(segment, inherited_type)]
    if len(benefit_segments) >= 2:
        return benefit_segments
    return [line]


def _strip_split_label(label: str) -> str:
    cleaned = re.sub(r"^\[[^\]]+\]\s*", "", label).strip()
    if "-" in cleaned:
        prefix, suffix = cleaned.rsplit("-", 1)
        if any(marker in prefix for marker in ("진심", "서비스", "선택")):
            cleaned = suffix.strip()
    return cleaned.strip(" ,/·")


def _token_category(token: str) -> str | None:
    cleaned = _strip_split_label(token)
    compact = _compact(cleaned)
    for keyword, category in SPLIT_CATEGORY_ALIASES.items():
        if _compact(keyword) in compact:
            return category
    category = map_service_category("", cleaned, "")
    if category != "ETC":
        return category
    return None


def _split_label_targets(label: str) -> list[str]:
    cleaned = _strip_split_label(label)
    if not cleaned:
        return []

    separators = r"\s*/\s*|\s+·\s+|,\s*"
    parts = [part.strip(" ,/·") for part in re.split(separators, cleaned) if part.strip(" ,/·")]
    if len(parts) < 2:
        return [cleaned]

    categories = [_token_category(part) for part in parts]
    distinct_categories = {category for category in categories if category}
    if len(distinct_categories) >= 2 and all(categories):
        return parts
    return [cleaned]


def _default_suffix(inherited_type: str | None) -> str:
    if inherited_type == "CASHBACK":
        return "캐시백"
    if inherited_type == "MILEAGE":
        return "적립"
    return "할인"


def _label_matches(target: str, candidate: str) -> bool:
    target_compact = _compact(target)
    candidate_compact = _compact(candidate)
    if target_compact in candidate_compact or candidate_compact in target_compact:
        return True
    if target_compact == "배달" and "배달앱" in candidate_compact:
        return True
    return False


def _detail_context_for_target(target: str, detail: str) -> str:
    for line in detail.splitlines():
        cleaned = line.strip().lstrip("-*※ ").strip()
        if not cleaned:
            continue

        for label, body in re.findall(r"([가-힣A-Za-z0-9+/ ]{1,24})\(([^)]{1,120})\)", cleaned):
            if _label_matches(target, label):
                return f"{label.strip()}({body.strip()})"

        colon_match = re.match(r"([^:：]{1,40})[:：]\s*(.+)", cleaned)
        if not colon_match:
            continue
        labels_text, body = colon_match.groups()
        labels = [part.strip() for part in re.split(r"\s*/\s*|,\s*", labels_text) if part.strip()]
        if not any(_label_matches(target, label) for label in labels):
            continue
        brands = extract_brand_names("", body, "")
        if brands:
            return f"{target}: {', '.join(brands)}"
    return ""


def _compact_benefit_header(text: str) -> str:
    cleaned = re.sub(r"^\[[^\]]+\]\s*", "", normalize_spaces(text or ""))
    return _compact(cleaned.strip(" ,/·"))


def _detail_line_matches_benefit(benefit_line: str, detail_line: str) -> bool:
    benefit_key = _compact_benefit_header(benefit_line)
    detail_key = _compact_benefit_header(detail_line)
    if not benefit_key or not detail_key:
        return False
    return benefit_key in detail_key or detail_key in benefit_key


def _detail_section_for_benefit_line(benefit_line: str, detail: str) -> str:
    detail_lines = [line.strip() for line in detail.splitlines() if line.strip()]
    start_index = None

    for index, line in enumerate(detail_lines):
        cleaned = line.lstrip("-*※ ").strip()
        if _detail_line_matches_benefit(benefit_line, cleaned):
            start_index = index
            break

    if start_index is None:
        return ""

    section: list[str] = []
    for line in detail_lines[start_index:]:
        cleaned = line.lstrip("-*※ ").strip()
        if section and _is_benefit_line(cleaned):
            break
        section.append(line)
    return "\n".join(section)


def _expand_rate_groups(line: str, inherited_type: str | None, detail: str) -> list[str]:
    source = re.sub(r"^\[[^\]]+\]\s*", "", line).strip()
    matches = list(VALUE_WITH_SUFFIX_RE.finditer(source))
    if not matches:
        return [line]

    expanded: list[str] = []
    cursor = 0
    for match in matches:
        label = source[cursor:match.start()].strip(" ,/·")
        value = normalize_spaces(match.group(1))
        suffix = normalize_spaces(match.group(2) or _default_suffix(inherited_type))
        cursor = match.end()

        targets = _split_label_targets(label)
        if not targets:
            continue
        for target in targets:
            context = _detail_context_for_target(target, detail)
            target_text = context or _strip_split_label(target)
            expanded.append(normalize_spaces(f"{target_text} {value} {suffix}"))

    if len(expanded) >= 2:
        return expanded
    return [line]


def _shared_limit_note(text: str) -> str:
    lines = []
    source_lines = [normalize_spaces(line) for line in text.splitlines() if normalize_spaces(line)]
    for index, line in enumerate(source_lines):
        cleaned = normalize_spaces(line)
        if cleaned and SHARED_LIMIT_RE.search(cleaned):
            lines.append(cleaned)
            lines.extend(source_lines[index + 1:index + 3])
    return " / ".join(lines[:4])[:160]


def _shared_limit_tag(card: dict, source_order: int, note: str) -> str:
    source_card_id = str(card.get("card_id"))
    return f"[SHARED_LIMIT group=card_{source_card_id}_{source_order}] 원문: {note}"


def _card_shared_limit_note(card: dict) -> str:
    note_source = []
    for benefit in card.get("benefits") or []:
        main_title = benefit.get("main_title") or ""
        sub_title = benefit.get("sub_title") or ""
        if is_notice(main_title, sub_title):
            note_source.append(benefit.get("detail") or "")
    return _shared_limit_note("\n".join(note_source))


TARGET_HEADER_HINTS = ("할인 대상", "할인대상", "대상 가맹점", "대상가맹점", "적립 대상", "적립대상")
IGNORE_TABLE_HINTS = ("연회비", "수수료", "환율", "유의사항", "전월 이용금액 기준", "서비스 이용 방법", "추가 차감")


def _table_text(table: dict) -> str:
    return "\n".join(
        part
        for part in [
            table.get("context") or "",
            " ".join(table.get("headers") or []),
            "\n".join(" ".join(row) for row in table.get("rows") or []),
        ]
        if part
    )


def _table_headers(table: dict) -> list[str]:
    return [normalize_spaces(header) for header in table.get("headers") or [] if normalize_spaces(header)]


def _table_rows(table: dict) -> list[list[str]]:
    return [[normalize_spaces(cell) for cell in row] for row in table.get("rows") or [] if any(normalize_spaces(cell) for cell in row)]


def _table_data_rows(table: dict) -> list[list[str]]:
    rows = _table_rows(table)
    if not rows:
        return []
    first = " ".join(rows[0])
    if any(hint in first for hint in ("구분", "영역", "업종", "할인 대상", "할인대상", "대상 가맹점")):
        return rows[1:]
    return rows


def _is_ignored_table(table: dict) -> bool:
    context = table.get("context") or ""
    return any(hint in context for hint in IGNORE_TABLE_HINTS)


def _money_band_min(text: str) -> int | None:
    match = re.search(r"(\d+(?:\.\d+)?)\s*만\s*원?\s*이상", text or "")
    if not match:
        return None
    return int(float(match.group(1)) * 10_000)


def _is_limit_table(table: dict) -> bool:
    headers = _table_headers(table)
    rows = _table_rows(table)
    if sum(1 for header in headers if _money_band_min(header) is not None) >= 2:
        return True
    if rows and sum(1 for cell in rows[0] if _money_band_min(cell) is not None) >= 2:
        return True
    return False


def _limit_specs_from_table(table: dict) -> list[dict[str, Any]]:
    headers = _table_headers(table)
    rows = _table_rows(table)
    band_headers = headers
    amount_row: list[str] | None = None

    if sum(1 for header in band_headers if _money_band_min(header) is not None) < 2 and rows:
        band_headers = rows[0]
        rows = rows[1:]

    if sum(1 for header in band_headers if _money_band_min(header) is not None) < 2:
        return []

    for row in rows:
        amounts = [normalize_money(cell) for cell in row]
        if sum(1 for amount in amounts if amount is not None) >= 2:
            amount_row = row
            break
    if not amount_row:
        return []

    specs: list[dict[str, Any]] = []
    bands = [_money_band_min(header) for header in band_headers]
    for index, min_usage in enumerate(bands):
        if min_usage is None or index >= len(amount_row):
            continue
        monthly_limit = normalize_money(amount_row[index])
        if monthly_limit is None:
            continue
        next_min = next((band for band in bands[index + 1:] if band is not None), None)
        specs.append(
            {
                "min_prev_month_usage": min_usage,
                "max_prev_month_usage": next_min,
                "monthly_limit_amount": monthly_limit,
                "table_limit_desc": f"{band_headers[index]}: {amount_row[index]}",
            }
        )
    return specs


def _limit_specs_from_tables(tables: list[dict]) -> list[dict[str, Any]]:
    for table in tables:
        specs = _limit_specs_from_table(table)
        if specs:
            return specs
    return []


def _target_column_index(headers: list[str], row: list[str]) -> int:
    for index, header in enumerate(headers):
        if any(hint in header for hint in TARGET_HEADER_HINTS):
            return index
    return 1 if len(row) > 1 else 0


def _table_row_category(label: str, target_text: str = "") -> str | None:
    compact_label = _compact(label)
    if re.fullmatch(r"[①②③④⑤⑥⑦⑧⑨⑩\d]+", compact_label):
        return None
    if re.fullmatch(r"\d+(?:\.\d+)?%", compact_label):
        return None
    if normalize_money(label) is not None or _money_band_min(label) is not None:
        return None

    category = _token_category(label)
    if category:
        return category
    category = map_service_category("", label, target_text)
    if category != "ETC":
        return category
    return None


def _is_target_table(table: dict) -> bool:
    if _is_ignored_table(table) or _is_limit_table(table):
        return False

    headers = _table_headers(table)
    if any(any(hint in header for hint in TARGET_HEADER_HINTS) for header in headers):
        return True

    data_rows = _table_data_rows(table)
    category_rows = 0
    for row in data_rows:
        if len(row) < 2:
            continue
        label = row[0]
        target_text = row[_target_column_index(headers, row)]
        if _table_row_category(label, target_text):
            category_rows += 1
    return category_rows >= 2


def _benefit_value_phrase(main_title: str, sub_title: str, detail: str) -> str:
    source = f"{sub_title}\n{detail}"
    match = VALUE_WITH_SUFFIX_RE.search(source)
    if match:
        value = normalize_spaces(match.group(1))
        suffix = normalize_spaces(match.group(2) or _default_suffix(infer_benefit_type(main_title, sub_title, detail)))
        return normalize_spaces(f"{value} {suffix}")
    unit_reward = parse_unit_reward_rate(source)
    if unit_reward:
        return normalize_spaces(unit_reward.get("raw") or "적립")
    return _default_suffix(infer_benefit_type(main_title, sub_title, detail))


def _contextual_brand_names(label: str, target_text: str, brand_candidates: list[str] | None = None) -> list[str]:
    text = f"{label} {target_text}"
    brand_names = extract_brand_names("", text, "", brand_candidates)
    compact_target = _compact(target_text)
    additions: list[str] = []

    if "백화점" in label:
        if "롯데" in compact_target:
            additions.append("롯데백화점")
        if "현대" in compact_target:
            additions.append("현대백화점")
        if "신세계" in compact_target:
            additions.append("신세계백화점")
    if "아울렛" in label:
        if "롯데" in compact_target:
            additions.append("롯데프리미엄아울렛")
        if "현대" in compact_target:
            additions.append("현대프리미엄아울렛")
        if "신세계" in compact_target:
            additions.append("신세계사이먼")
    if "현대오일뱅크" in target_text and "현대오일뱅크" not in brand_names:
        additions.append("현대오일뱅크")

    return list(dict.fromkeys([*brand_names, *additions]))


def _split_table_row_categories(label: str, target_text: str) -> list[tuple[str, str, str]]:
    category = _table_row_category(label, target_text)
    if not category:
        return []
    if label == "의료" and "약국" in target_text:
        return [
            ("의료", "병·의원, 동물병원", "HEALTH"),
            ("약국", "약국", "PHARMACY"),
        ]
    return [(label, target_text, category)]


def _target_items_from_tables(
    card: dict,
    benefit: dict,
    original_order: int,
    card_shared_limit_note: str,
    brand_candidates: list[str] | None = None,
) -> list[dict]:
    tables = benefit.get("tables") or []
    target_tables = [table for table in tables if _is_target_table(table)]
    if not target_tables:
        return []

    main_title = benefit.get("main_title") or ""
    sub_title = benefit.get("sub_title") or ""
    detail = benefit.get("detail") or ""
    value_phrase = _benefit_value_phrase(main_title, sub_title, detail)
    limit_specs = _limit_specs_from_tables(tables)
    original_desc = _benefit_desc(sub_title, detail)
    shared_note = _shared_limit_note(f"{sub_title}\n{detail}") or card_shared_limit_note
    shared_tag = _shared_limit_tag(card, original_order, shared_note) if shared_note else None

    items: list[dict] = []
    split_order = 1
    for table in target_tables:
        headers = _table_headers(table)
        target_index = None
        for row in _table_data_rows(table):
            if len(row) < 2:
                continue
            if target_index is None:
                target_index = _target_column_index(headers, row)
            if target_index >= len(row):
                continue
            raw_label = row[0]
            raw_target = row[target_index]
            if not raw_label or not raw_target:
                continue
            if is_third_party_pay_benefit("", raw_label, "") or is_third_party_pay_benefit("", raw_target, ""):
                continue
            for label, target_text, category in _split_table_row_categories(raw_label, raw_target):
                table_brands = _contextual_brand_names(label, target_text, brand_candidates)
                item_sub_title = normalize_spaces(f"{label} {value_phrase}")
                table_detail = "\n".join(
                    part
                    for part in [
                        f"표 대상: {label} - {target_text}",
                        table.get("context") or "",
                        detail,
                    ]
                    if part
                )
                items.append(
                    {
                        **benefit,
                        "main_title": "",
                        "sub_title": item_sub_title,
                        "detail": table_detail,
                        "source_order": original_order,
                        "split_order": split_order,
                        "order_key": f"{original_order}_{split_order}",
                        "description_override": original_desc,
                        "shared_limit_tag": shared_tag,
                        "table_source": True,
                        "table_service_category": category,
                        "table_brand_names": table_brands,
                        "table_limit_specs": limit_specs,
                        "table_target_label": label,
                        "table_target_text": target_text,
                    }
                )
                split_order += 1
    return items


def _apply_table_limit_specs(tiers: list[dict[str, Any]], specs: list[dict[str, Any]]) -> list[dict[str, Any]]:
    if not specs or not tiers:
        return tiers
    base = tiers[0]
    result: list[dict[str, Any]] = []
    for spec in specs:
        tier = {
            **base,
            "min_prev_month_usage": spec["min_prev_month_usage"],
            "max_prev_month_usage": spec["max_prev_month_usage"],
            "monthly_limit_amount": spec["monthly_limit_amount"],
        }
        desc = tier.get("tier_desc") or ""
        limit_desc = f"[TABLE_LIMIT {spec['table_limit_desc']}]"
        tier["tier_desc"] = f"{limit_desc} | {desc}" if desc else limit_desc
        result.append(tier)
    return result


def expand_benefit_items(card: dict, benefit: dict, original_order: int, card_shared_limit_note: str = "") -> list[dict]:
    main_title = benefit.get("main_title") or ""
    sub_title = benefit.get("sub_title") or ""
    detail = benefit.get("detail") or ""

    if not (
        is_notice(main_title, sub_title)
        or is_overseas(main_title, sub_title)
        or is_third_party_pay_benefit(main_title, sub_title, detail)
        or is_premium_or_voucher(main_title, sub_title)
        or is_non_payment_benefit(main_title, sub_title)
        or is_selectable_notice_only(main_title, sub_title, detail)
    ):
        table_items = _target_items_from_tables(card, benefit, original_order, card_shared_limit_note)
        if table_items:
            return table_items

    lines = [line.strip().strip(",") for line in sub_title.splitlines() if line.strip()]
    inherited_type = infer_benefit_type(main_title, sub_title, detail)

    if not lines:
        return [
            {
                **benefit,
                "source_order": original_order,
                "split_order": 1,
                "order_key": str(original_order),
                "description_override": _benefit_desc(sub_title, detail),
            }
        ]

    benefit_lines: list[str] = []
    context_lines: list[str] = []

    for line in lines:
        if is_overseas("", line) or is_third_party_pay_benefit("", line, ""):
            context_lines.append(f"[LINE_SKIP] {line}")
            continue
        rate_group_lines = _expand_rate_groups(line, inherited_type, detail)
        if len(rate_group_lines) > 1:
            benefit_lines.extend(rate_group_lines)
            continue
        segments = _split_segments(line, inherited_type)
        if len(segments) > 1:
            benefit_lines.extend(segments)
            continue
        if _is_benefit_line(line, inherited_type):
            benefit_lines.append(line)
        else:
            context_lines.append(line)

    if not benefit_lines:
        return [
            {
                **benefit,
                "source_order": original_order,
                "split_order": 1,
                "order_key": str(original_order),
                "description_override": _benefit_desc(sub_title, detail),
            }
        ]

    if len(benefit_lines) == 1 and len(lines) == 1:
        return [
            {
                **benefit,
                "source_order": original_order,
                "split_order": 1,
                "order_key": str(original_order),
                "description_override": _benefit_desc(sub_title, detail),
            }
        ]

    common_detail = "\n".join([line for line in context_lines if not _is_meta_line(line)])
    if detail:
        common_detail = "\n".join(part for part in [common_detail, detail] if part)

    expanded = []
    original_desc = _benefit_desc(sub_title, detail)
    shared_note = _shared_limit_note(f"{sub_title}\n{detail}") if len(benefit_lines) > 1 else ""
    if not shared_note and len(benefit_lines) > 1:
        shared_note = card_shared_limit_note
    shared_tag = _shared_limit_tag(card, original_order, shared_note) if shared_note else None
    for split_order, line in enumerate(benefit_lines, start=1):
        line_detail = _detail_section_for_benefit_line(line, detail) or common_detail
        expanded.append(
            {
                **benefit,
                "main_title": main_title,
                "sub_title": line,
                "detail": line_detail,
                "source_order": original_order,
                "split_order": split_order,
                "order_key": f"{original_order}_{split_order}",
                "description_override": original_desc,
                "shared_limit_tag": shared_tag,
            }
        )
    return expanded


def _add_skip(stats: Counter, skip_comments: list[str], card: dict, order: Any, reason: str, benefit: dict) -> None:
    stats[SKIP_COUNTERS[reason]] += 1
    skip_comments.append(_skip_sql_comment(card, order, reason, benefit))


def _build_header(summary: dict[str, Any], cards_json_path: str | Path, ranks_json_path: str | Path) -> str:
    summary_lines = json.dumps(summary, ensure_ascii=False, indent=2).splitlines()
    commented_summary = "\n".join(f"-- {line}" for line in summary_lines)
    return "\n".join(
        [
            "-- ErumPay card_db Card Gorilla seed SQL",
            f"-- generated_at: {datetime.now().isoformat(timespec='seconds')}",
            "-- source: Card Gorilla",
            f"-- input_cards_json: {cards_json_path}",
            f"-- input_ranks_json: {ranks_json_path}",
            "--",
            "-- ASSUMPTIONS:",
            "-- - Target schema follows docs/이룸_명세서.xlsx table spec.",
            "-- - card_benefit_brand must exist with UNIQUE(benefit_id, brand_name).",
            "-- - benefit_desc max length is treated as 500 and tier_desc max length as 500.",
            "-- - selectable benefits are seeded as all numeric candidates because user selected option state is not modeled yet.",
            "-- - automatically detected brand candidates require human review before production use.",
            "-- - unit rewards are conservatively converted with 1 mile/point = 1 KRW and original text is preserved in tier_desc.",
            "-- - split benefits with shared monthly/yearly limits keep [SHARED_LIMIT ...] source notes in tier_desc; exact monthly aggregation requires recommendation-service handling.",
            "-- - card_benefit.priority is seeded as 0; source order is used only for generated SQL variables/comments.",
            "-- - card_benefit has no source benefit natural key; this seed uses a best-effort predicate on current columns to avoid duplicates when the same SQL is re-run.",
            "-- - generated_* counters mean generated SQL statements, not actual DB affected rows after NOT EXISTS guards.",
            "-- - for full re-crawl/re-seed, review cleanup policy for old master rows before running this file.",
            "--",
            "-- SUMMARY:",
            commented_summary,
            "",
        ]
    )


def _print_dry_run(summary: dict[str, Any]) -> None:
    print(json.dumps(summary, ensure_ascii=False, indent=2))


def _process_benefit(
    card: dict,
    benefit: dict,
    benefit_order: Any,
    brand_candidates: list[str],
    stats: Counter,
    skip_comments: list[str],
    warning_comments: list[str],
    possible_brand_review_items: list[dict],
) -> tuple[str | None, list[str], list[str]]:
    main_title = benefit.get("main_title") or ""
    sub_title = benefit.get("sub_title") or ""
    detail = benefit.get("detail") or ""

    if is_notice(main_title, sub_title):
        _add_skip(stats, skip_comments, card, benefit_order, "NOTICE", benefit)
        return None, [], []
    if is_overseas(main_title, sub_title):
        _add_skip(stats, skip_comments, card, benefit_order, "OVERSEAS", benefit)
        return None, [], []
    if is_third_party_pay_benefit(main_title, sub_title, detail):
        _add_skip(stats, skip_comments, card, benefit_order, "THIRD_PARTY_PAY", benefit)
        return None, [], []
    if is_premium_or_voucher(main_title, sub_title):
        _add_skip(stats, skip_comments, card, benefit_order, "PREMIUM_OR_VOUCHER", benefit)
        return None, [], []
    if is_non_payment_benefit(main_title, sub_title):
        _add_skip(stats, skip_comments, card, benefit_order, "NON_PAYMENT_BENEFIT", benefit)
        return None, [], []
    if is_selectable_notice_only(main_title, sub_title, detail):
        _add_skip(stats, skip_comments, card, benefit_order, "SELECTABLE_NOTICE_ONLY", benefit)
        return None, [], []

    benefit_type = infer_benefit_type(main_title, sub_title, detail)
    if benefit_type is None:
        _add_skip(stats, skip_comments, card, benefit_order, "UNSUPPORTED_TYPE", benefit)
        return None, [], []

    if "[SELECT" in sub_title or "진심" in sub_title or "선택" in main_title:
        stats["selectable_benefits_seen"] += 1

    table_brand_names = benefit.get("table_brand_names")
    brand_names = table_brand_names if table_brand_names is not None else extract_brand_names(main_title, sub_title, detail, brand_candidates)
    detail_only_brand_names = [] if benefit.get("table_source") else extract_detail_only_brand_candidates(main_title, sub_title, detail, brand_candidates)
    if detail_only_brand_names:
        possible_brand_review_items.append(
            {
                "source_card_id": card.get("card_id"),
                "order": benefit_order,
                "detail_only_brand_names": detail_only_brand_names[:8],
                "title": normalize_spaces(main_title or sub_title),
            }
        )

    if not benefit.get("table_source") and is_brand_restricted(main_title, sub_title, detail) and not brand_names:
        _add_skip(stats, skip_comments, card, benefit_order, "BRAND_WITHOUT_KEYWORD", benefit)
        return None, [], []

    if brand_names:
        if is_review_brand_group(brand_names):
            possible_brand_review_items.append(
                {
                    "source_card_id": card.get("card_id"),
                    "order": benefit_order,
                    "brand_names": brand_names,
                    "title": normalize_spaces(main_title or sub_title),
                }
            )

    value_text = f"{sub_title}\n{detail}".strip()
    unit_probe = parse_unit_reward_rate(value_text)
    if unit_probe and unit_probe.get("too_small"):
        _add_skip(stats, skip_comments, card, benefit_order, "UNIT_REWARD_TOO_SMALL", benefit)
        return None, [], []

    tiers = parse_tiers(card.get("before_month"), value_text)
    if not tiers:
        clean_value_text = strip_exclusion_sections(value_text)
        parsed_rate = parse_rate(clean_value_text)
        if parsed_rate is not None and parsed_rate >= 100:
            _add_skip(stats, skip_comments, card, benefit_order, "INVALID_RATE", benefit)
        else:
            _add_skip(stats, skip_comments, card, benefit_order, "NO_TIER_VALUE", benefit)
        return None, [], []

    if unit_probe:
        stats["unit_reward_converted"] += 1

    table_limit_specs = benefit.get("table_limit_specs") or []
    if table_limit_specs:
        tiers = _apply_table_limit_specs(tiers, table_limit_specs)
        stats["table_limit_tier_groups"] += len(table_limit_specs)

    shared_limit_tag = benefit.get("shared_limit_tag")
    if shared_limit_tag:
        stats["shared_limit_tagged_tiers"] += len(tiers)
        for tier in tiers:
            tier_desc = tier.get("tier_desc") or ""
            tier["tier_desc"] = f"{shared_limit_tag} | {tier_desc}" if tier_desc else shared_limit_tag

    category_main_title = "" if benefit.get("table_source") or str(benefit_order) != str(benefit.get("source_order", benefit_order)) else main_title
    service_category = benefit.get("table_service_category") or map_service_category(category_main_title, sub_title, detail)
    if service_category == "ETC":
        stats["mapped_etc_category"] += 1

    representative_sub_title, is_multiline, desc_sub_title = split_representative_line(sub_title, detail)
    if is_multiline:
        stats["multi_line_benefits"] += 1
        warning_comments.append(
            f"-- MULTILINE benefit: source_card_id={card.get('card_id')}, order={benefit_order} (대표 줄만 파싱, 원문 보존)"
        )

    description = benefit.get("description_override") or _benefit_desc(desc_sub_title or representative_sub_title or sub_title, detail)
    description, truncated, original_length = truncate_text(description, BENEFIT_DESC_MAX_LENGTH)
    if truncated:
        stats["truncated_benefit_desc"] += 1
        warning_comments.append(
            f"-- WARNING truncated benefit_desc: source_card_id={card.get('card_id')}, order={benefit_order}, original_length={original_length}, max_length={BENEFIT_DESC_MAX_LENGTH}"
        )

    for tier in tiers:
        tier_desc, truncated_tier, original_tier_length = truncate_text(tier.get("tier_desc"), TIER_DESC_MAX_LENGTH)
        tier["tier_desc"] = tier_desc
        if truncated_tier:
            stats["truncated_tier_desc"] += 1
            warning_comments.append(
                f"-- WARNING truncated tier_desc: source_card_id={card.get('card_id')}, order={benefit_order}, original_length={original_tier_length}, max_length={TIER_DESC_MAX_LENGTH}"
            )

    min_amount = parse_min_amount(value_text)
    time_start, time_end = parse_time_condition(value_text)
    day_condition = parse_day_condition(value_text)

    benefit_sql = generate_card_benefit_sql(
        card=card,
        benefit=benefit,
        benefit_order=benefit_order,
        tiers=tiers,
        benefit_desc=description,
        service_category=service_category,
        benefit_type=benefit_type,
        min_amount=min_amount,
        time_start=time_start,
        time_end=time_end,
        day_condition=day_condition,
    )
    brand_sql = generate_card_benefit_brand_sql(card, benefit, benefit_order, brand_names)
    tier_sql = [generate_card_benefit_tier_sql(card, benefit, benefit_order, tier) for tier in tiers]

    stats["generated_benefit_sql_count"] += 1
    stats["generated_brand_sql_count"] += len(brand_sql)
    stats["generated_tier_sql_count"] += len(tier_sql)
    if brand_names:
        stats["brand_restricted_benefits"] += 1
    if "[SELECT" in sub_title or "진심" in sub_title or "선택" in main_title:
        stats["generated_selectable_benefit_sql_count"] += 1

    return benefit_sql, brand_sql, tier_sql


def _summary(
    stats: Counter,
    total_cards: int,
    total_benefits: int,
    detected_brand_candidates: list[str],
    used_brand_names: set[str],
    possible_brand_review_items: list[dict],
    mapped_other_card_company: list[str],
    mock_bin_overflow: list[str],
    failed_cards: list[str],
    failed_benefits: list[str],
) -> dict[str, Any]:
    keys = [
        "generated_card_product_sql_count",
        "generated_benefit_sql_count",
        "generated_brand_sql_count",
        "generated_tier_sql_count",
        "brand_restricted_benefits",
        "unit_reward_converted",
        "expanded_benefit_items",
        "split_benefit_source_rows",
        "split_benefit_items",
        "table_benefit_source_rows",
        "table_benefit_items",
        "table_limit_tier_groups",
        "shared_limit_tagged_tiers",
        "selectable_benefits_seen",
        "generated_selectable_benefit_sql_count",
        "multi_line_benefits",
        "skipped_notices",
        "skipped_overseas",
        "skipped_third_party_pay",
        "skipped_premium_or_voucher",
        "skipped_non_payment_benefit",
        "skipped_unsupported_type",
        "skipped_selectable_notice_only",
        "skipped_brand_restricted_without_keyword",
        "skipped_no_tier_value",
        "skipped_invalid_rate",
        "skipped_unit_reward_too_small",
        "mapped_etc_category",
        "truncated_benefit_desc",
        "truncated_tier_desc",
        "parse_warnings",
    ]
    result = {
        "total_cards": total_cards,
        "total_benefits_seen": total_benefits,
    }
    for key in keys:
        result[key] = stats[key]
    result.update(
        {
            "detected_brand_candidates": detected_brand_candidates[:80],
            "used_brand_names": sorted(used_brand_names),
            "possible_brand_review_items": possible_brand_review_items[:80],
            "mapped_other_card_company": mapped_other_card_company,
            "mock_bin_overflow": mock_bin_overflow,
            "failed_cards": failed_cards,
            "failed_benefits": failed_benefits[:80],
        }
    )
    return result


def generate_seed_sql(cards_json_path: str | Path, ranks_json_path: str | Path, output_path: str | Path, dry_run: bool = False) -> dict[str, Any]:
    cards = load_json(cards_json_path)
    ranks = load_json(ranks_json_path)
    if not isinstance(cards, list):
        raise ValueError("cards-json must contain a list")
    if not isinstance(ranks, list):
        raise ValueError("ranks-json must contain a list")

    rank_map = build_rank_map(ranks)
    mock_bin_map, mapped_other_card_company, mock_bin_overflow = build_mock_bin_map(cards)
    detected_brand_candidates = extract_brand_candidates_from_cards(cards)
    used_brand_names: set[str] = set()
    possible_brand_review_items: list[dict] = []

    stats: Counter = Counter()
    failed_cards: list[str] = []
    failed_benefits: list[str] = []
    product_sql: list[str] = []
    benefit_sql: list[str] = []
    brand_sql: list[str] = []
    tier_sql: list[str] = []
    skip_comments: list[str] = []
    warning_comments: list[str] = []

    for card in cards:
        source_card_id = str(card.get("card_id"))
        card_shared_limit_note = _card_shared_limit_note(card)
        try:
            mock_bin = mock_bin_map.get(source_card_id)
            if not mock_bin:
                failed_cards.append(f"{source_card_id}: mock_bin not generated")
                continue
            product_sql.append(generate_card_product_sql(card, rank_map.get(source_card_id), mock_bin))
            stats["generated_card_product_sql_count"] += 1
        except Exception as exc:
            failed_cards.append(f"{source_card_id}: {exc}")
            continue

        for benefit_order, benefit in enumerate(card.get("benefits") or [], start=1):
            stats["total_benefits_seen"] += 1
            try:
                is_source_multiline = len([line for line in (benefit.get("sub_title") or "").splitlines() if line.strip()]) > 1
                expanded_benefits = expand_benefit_items(card, benefit, benefit_order, card_shared_limit_note)
                stats["expanded_benefit_items"] += len(expanded_benefits)
                if any(item.get("table_source") for item in expanded_benefits):
                    stats["table_benefit_source_rows"] += 1
                    stats["table_benefit_items"] += len(expanded_benefits)
                if len(expanded_benefits) > 1:
                    if is_source_multiline:
                        stats["multi_line_benefits"] += 1
                    stats["split_benefit_source_rows"] += 1
                    stats["split_benefit_items"] += len(expanded_benefits)
                    warning_comments.append(
                        f"-- SPLIT benefit: source_card_id={source_card_id}, order={benefit_order}, split_items={len(expanded_benefits)} (independent benefit lines parsed separately, priority=0)"
                    )
                for expanded_benefit in expanded_benefits:
                    generated_benefit_sql, generated_brand_sql, generated_tier_sql = _process_benefit(
                        card=card,
                        benefit=expanded_benefit,
                        benefit_order=expanded_benefit.get("order_key") or benefit_order,
                        brand_candidates=detected_brand_candidates,
                        stats=stats,
                        skip_comments=skip_comments,
                        warning_comments=warning_comments,
                        possible_brand_review_items=possible_brand_review_items,
                    )
                    if generated_benefit_sql:
                        benefit_sql.append(generated_benefit_sql)
                        brand_sql.extend(generated_brand_sql)
                        tier_sql.extend(generated_tier_sql)
                        for statement in generated_brand_sql:
                            match = re.search(r"brand=([^\n]+)", statement)
                            if match:
                                used_brand_names.add(match.group(1).strip())
            except Exception as exc:
                stats["parse_warnings"] += 1
                failed_benefits.append(f"{source_card_id}:{benefit_order}: {exc}")

    summary = _summary(
        stats=stats,
        total_cards=len(cards),
        total_benefits=stats["total_benefits_seen"],
        detected_brand_candidates=detected_brand_candidates,
        used_brand_names=used_brand_names,
        possible_brand_review_items=possible_brand_review_items,
        mapped_other_card_company=mapped_other_card_company,
        mock_bin_overflow=mock_bin_overflow,
        failed_cards=failed_cards,
        failed_benefits=failed_benefits,
    )

    if dry_run:
        _print_dry_run(summary)
        return summary

    output = Path(output_path)
    output.parent.mkdir(parents=True, exist_ok=True)

    sample_comments = warning_comments[:250] + skip_comments[:250]

    sql_parts = [
        _build_header(summary, cards_json_path, ranks_json_path),
        "SET NAMES utf8mb4;",
        "USE card_db;",
        "",
        "START TRANSACTION;",
        "",
        "-- =========================================================",
        "-- card_product seed",
        "-- =========================================================",
        "\n\n".join(product_sql),
        "",
        "-- =========================================================",
        "-- card_benefit seed",
        "-- =========================================================",
        "\n\n".join(benefit_sql),
        "",
        "-- =========================================================",
        "-- card_benefit_brand seed",
        "-- =========================================================",
        "\n\n".join(brand_sql),
        "",
        "-- =========================================================",
        "-- card_benefit_tier seed",
        "-- =========================================================",
        "\n\n".join(tier_sql),
        "",
        "-- =========================================================",
        "-- skipped/warning samples",
        "-- =========================================================",
        "\n".join(sample_comments),
        "",
        "COMMIT;",
        "",
        "-- If execution fails before COMMIT, run ROLLBACK in the same MySQL session and inspect the failing statement.",
        "-- If COMMIT already completed, rollback is not possible; review cleanup policy before re-seeding.",
        "",
    ]
    output.write_text("\n".join(sql_parts), encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    print(f"\nWrote SQL: {output}")
    return summary


def run_self_tests() -> None:
    assert parse_annual_fee("국내전용 10,000원 해외겸용 12,000원") == 10000
    assert parse_annual_fee("국내전용 1만원 해외겸용 1만2천원") == 10000
    assert parse_annual_fee("국내전용 1만5천원 해외겸용 2만원") == 15000
    assert parse_annual_fee("해외겸용 1만5천원") == 15000
    assert parse_tiers("전월실적30만원 이상", "10% 청구할인")[0]["min_prev_month_usage"] == 300000
    assert infer_benefit_type("", "10% 청구할인", "") == "DISCOUNT"
    assert infer_benefit_type("", "3만원 캐시백", "") == "CASHBACK"
    point = parse_unit_reward_rate("1,000원당 1포인트 적립")
    assert point and point["unit_type"] == "POINT" and str(point["rate"]) == "0.100"
    mile = parse_unit_reward_rate("1,500원당 1마일 적립")
    assert mile and mile["unit_type"] == "MILE" and str(mile["rate"]) == "0.067"
    assert parse_unit_reward_rate("K-패스 마일리지 적립") is None
    assert is_premium_or_voucher("공항라운지/PP", "")
    assert is_premium_or_voucher("", "유튜브프리미엄 정기결제 20% 청구할인")
    assert not is_premium_or_voucher("", "프리미엄 아울렛 10% 청구할인")
    assert is_non_payment_benefit("수수료우대", "")
    assert map_service_category("국내 모든 가맹점", "", "") == "ALL"
    assert map_service_category("국내외가맹점", "", "") == "ALL"
    assert map_service_category("베이커리", "", "") == "FOOD"
    assert map_service_category("테마파크", "", "") == "LEISURE"
    assert map_service_category("고속버스", "", "") == "TRANSIT"
    assert map_service_category("백화점", "", "") == "SHOPPING"
    assert not is_third_party_pay_benefit("카페", "5% 할인", "간편결제 제외")
    assert is_selectable_notice_only("", "[SELECT 1] 선택 옵션에 따른 할인 혜택 제공 (택 1)", "10% 할인")
    assert not is_selectable_notice_only("", "[SELECT 1] 국내 가맹점 0.7% 할인", "")
    brands = extract_brand_names("", "스타벅스, 폴바셋 10% 할인", "")
    assert brands == ["스타벅스", "폴바셋"]
    assert extract_brand_names("", "SSG COM, SSG.COM, SSG닷컴 7% 할인", "") == ["SSG.COM"]
    assert extract_brand_names("", "음식점/편의점/할인점/주유 7% 할인", "") == []
    tier = parse_tiers("", '카페 5% 할인\n전월실적 30만원 이상 / 월 할인한도 5,000원 / 1일 1회')[0]
    assert str(tier["rate"]) == "5.000"
    assert tier["min_prev_month_usage"] == 300000
    assert tier["monthly_limit_amount"] == 5000
    assert tier["daily_limit_count"] == 1
    assert parse_tiers("", "1만원 이상 결제 시 5% 할인")[0]["min_prev_month_usage"] == 0
    assert parse_tiers("전월실적40만원 이상", "국내 가맹점 0.7% 할인\n전월 이용금액에 관계없이")[0]["min_prev_month_usage"] == 0
    representative, is_multiline, desc_text = split_representative_line("지하철, 버스 7% 청구할인\nSKT, KT, LGU+ 7% 청구할인", "")
    assert is_multiline and "지하철" in representative and "SKT" in desc_text
    stream_delivery_split = expand_benefit_items(
        {"card_id": 666},
        {
            "main_title": "생활",
            "sub_title": "유튜브프리미엄, 넷플릭스, 멜론 정기결제 20% 청구할인\n배달의민족, 요기요 10% 청구할인",
            "detail": "[스트리밍/배달앱]\n유튜브프리미엄, 넷플릭스, 멜론 정기결제 20% 청구할인\n- 이용건당 7천원 이상 결제 시 제공\n배달의민족, 요기요 10% 청구할인\n- 이용건당 1만5천원 이상 결제 시 제공\n※ 스트리밍/배달앱 월 한도 5천원",
        },
        2,
    )
    assert len(stream_delivery_split) == 2
    assert parse_min_amount(f"{stream_delivery_split[0]['sub_title']}\n{stream_delivery_split[0]['detail']}") == 7000
    assert parse_min_amount(f"{stream_delivery_split[1]['sub_title']}\n{stream_delivery_split[1]['detail']}") == 15000
    eat_split = expand_benefit_items(
        {"card_id": 2441},
        {
            "main_title": "선택형",
            "sub_title": "[더욱 진심 서비스] 먹는데 진심-배달/커피 5% 할인",
            "detail": "먹는데 진심-배달/커피 5% 할인\n- 배달앱(배달의민족, 요기요, 마켓컬리), 커피(커피/음료전문업종)",
        },
        5,
        "더욱 진심 서비스 월 할인한도 / 택시, 커피",
    )
    assert len(eat_split) == 2
    assert "배달앱" in eat_split[0]["sub_title"] and "커피" in eat_split[1]["sub_title"]
    assert eat_split[0]["shared_limit_tag"]
    play_split = expand_benefit_items(
        {"card_id": 2441},
        {
            "main_title": "선택형",
            "sub_title": "[더욱 진심 서비스] 노는데 진심-택시/커피 5%, 영화관 30% 할인",
            "detail": "노는데 진심-택시/커피 5%, 영화관 30% 할인\n- 택시, 커피: 택시, 커피/음료전문점 업종\n- 영화관: CGV, 롯데시네마, 메가박스",
        },
        6,
    )
    assert [map_service_category("", item["sub_title"], "") for item in play_split] == ["TAXI", "CAFE", "LEISURE"]
    assert extract_brand_names("", play_split[2]["sub_title"], "") == ["롯데시네마", "메가박스", "CGV"]
    table_split = expand_benefit_items(
        {"card_id": 2885},
        {
            "main_title": "할인",
            "sub_title": "[SELECT 2] 온라인쇼핑몰/의료/배달앱 7% 할인",
            "detail": "온라인쇼핑/의료/배달앱 7% 할인\n전월 이용금액대별 통합 월 할인한도",
            "tables": [
                {
                    "context": "온라인쇼핑/의료/배달앱 7% 할인",
                    "headers": ["구분", "할인 대상"],
                    "rows": [
                        ["온라인쇼핑몰", "쿠팡, 네이버플러스 스토어, SSG COM, G마켓, 옥션, 11번가, 컬리, 삼성카드 쇼핑"],
                        ["의료", "병·의원, 약국, 동물병원"],
                        ["배달앱", "배달의민족, 쿠팡이츠, 요기요"],
                    ],
                },
                {
                    "context": "전월 이용금액대별 통합 월 할인한도",
                    "headers": ["40만원 이상", "80만원 이상", "120만원 이상"],
                    "rows": [["7,000원", "10,000원", "15,000원"]],
                },
            ],
        },
        6,
    )
    assert [item["table_service_category"] for item in table_split] == ["SHOPPING", "HEALTH", "PHARMACY", "FOOD"]
    assert table_split[0]["table_limit_specs"][0]["monthly_limit_amount"] == 7000
    assert "네이버플러스 스토어" in table_split[0]["table_brand_names"]
    assert "요기요" in table_split[3]["table_brand_names"]
    print("self-test passed")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate ErumPay card_db seed SQL from Card Gorilla JSON files.")
    parser.add_argument("--cards-json", default="./card_gorilla_cards.json")
    parser.add_argument("--ranks-json", default="./card_ids.json")
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT_PATH))
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if args.self_test:
        run_self_tests()
        return
    generate_seed_sql(
        cards_json_path=args.cards_json,
        ranks_json_path=args.ranks_json,
        output_path=args.output,
        dry_run=args.dry_run,
    )


if __name__ == "__main__":
    main()
