from __future__ import annotations

import json
import re
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path
from typing import Any


EXCLUSION_HEADINGS = (
    "유의사항",
    "공통 유의사항",
    "제외 대상",
    "할인 제외",
    "적립 제외",
    "캐시백 제외",
    "이용실적 제외",
    "전월 이용실적 제외",
    "할인/적립 제외 대상",
)

UNIT_REWARD_MILE_KEYWORDS = (
    "스카이패스",
    "SKYPASS",
    "대한항공",
    "아시아나",
    "항공마일리지",
    "마일리지",
    "마일",
)

UNIT_REWARD_POINT_KEYWORDS = (
    "마이신한포인트",
    "포인트리",
    "M포인트",
    "멤버십 리워즈",
    "리워즈",
    "포인트",
    "MR",
)

UNIT_REWARD_EXCLUDED_KEYWORDS = ("K-패스", "K패스", "기후동행")

RATE_SCALE = Decimal("0.001")
MONEY_PATTERN = (
    r"(?:\d+(?:\.\d+)?)\s*만\s*(?:\d+(?:\.\d+)?)\s*천\s*원|"
    r"(?:\d+(?:\.\d+)?)\s*만\s*(?:\d[\d,]*)\s*원|"
    r"(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?\s*(?:억원|만원|천원|원)"
)


def load_json(path: str | Path) -> Any:
    with Path(path).open("r", encoding="utf-8") as file:
        return json.load(file)


def build_rank_map(ranks_json: list[dict]) -> dict[str, dict]:
    return {str(item.get("card_id")): item for item in ranks_json if item.get("card_id") is not None}


def sql_literal(value: Any) -> str:
    if value is None:
        return "NULL"
    if isinstance(value, bool):
        return "TRUE" if value else "FALSE"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, Decimal):
        return format(value, "f")
    if isinstance(value, float):
        return str(value)

    text = str(value).replace("\x00", "")
    text = text.replace("\\", "\\\\")
    text = text.replace("'", "''")
    text = text.replace("\r\n", "\\n").replace("\n", "\\n").replace("\r", "\\n")
    text = text.replace("\t", "\\t")
    return f"'{text}'"


def strip_exclusion_sections(text: str | None) -> str:
    if not text:
        return ""
    cut_at = len(text)
    for heading in EXCLUSION_HEADINGS:
        index = text.find(heading)
        if index >= 0:
            cut_at = min(cut_at, index)
    return text[:cut_at]


def normalize_spaces(text: str | None) -> str:
    return re.sub(r"\s+", " ", text or "").strip()


def normalize_money(text: str | None) -> int | None:
    if not text:
        return None

    compact = re.sub(r"\s+", "", str(text)).replace(",", "")
    mixed = re.search(r"(\d+(?:\.\d+)?)만(?:(\d+(?:\.\d+)?)천)?(?:(\d+)원)?", compact)
    if mixed and (mixed.group(2) or mixed.group(3)):
        total = Decimal(mixed.group(1)) * 10_000
        if mixed.group(2):
            total += Decimal(mixed.group(2)) * 1_000
        if mixed.group(3):
            total += Decimal(mixed.group(3))
        return int(total)

    match = re.search(r"(\d+(?:\.\d+)?)억원", compact)
    if match:
        return int(Decimal(match.group(1)) * 100_000_000)

    match = re.search(r"(\d+(?:\.\d+)?)만원", compact)
    if match:
        return int(Decimal(match.group(1)) * 10_000)

    match = re.search(r"(\d+(?:\.\d+)?)천원", compact)
    if match:
        return int(Decimal(match.group(1)) * 1_000)

    match = re.search(r"(\d+)원", compact)
    if match:
        return int(match.group(1))

    match = re.search(r"^\d+$", compact)
    if match:
        return int(compact)

    return None


def parse_annual_fee(fee_text: str | None) -> int | None:
    if not fee_text:
        return None

    text = normalize_spaces(fee_text)
    domestic = re.search(r"국내전용\s*([0-9,]+)\s*원", text)
    if domestic:
        return int(domestic.group(1).replace(",", ""))

    domestic_text = re.search(r"국내전용\s*(.*?)(?:\s*해외겸용|$)", text)
    if domestic_text:
        domestic_amount = normalize_money(domestic_text.group(1))
        if domestic_amount is not None:
            return domestic_amount

    amounts = re.findall(r"([0-9][0-9,]*)\s*원", text)
    if amounts:
        return int(amounts[0].replace(",", ""))

    return normalize_money(text)


def parse_previous_month_usage(text: str | None) -> tuple[int | None, int | None] | None:
    if not text:
        return None

    if re.search(r"전월\s*(?:실적|이용금액)\s*에?\s*(?:관계없이|무관|없이|조건\s*없음)", text):
        return 0, None

    normalized = re.sub(r"\s+", "", text)
    if any(
        keyword in normalized
        for keyword in (
            "전월실적없음",
            "전월실적무관",
            "전월실적관계없이",
            "전월실적에관계없이",
            "전월이용금액관계없이",
            "전월이용금액에관계없이",
            "전월이용금액무관",
            "전월이용금액에무관",
            "전월실적조건없음",
            "전월이용금액조건없음",
            "전월실적없이",
            "전월이용금액없이",
            "무실적",
            "실적조건없음",
        )
    ):
        return 0, None

    range_match = re.search(
        r"(?:전월|지난달|직전\s*1개월)[^\n]{0,30}?(\d+(?:\.\d+)?)\s*만\s*원?\s*[~\-–]\s*(\d+(?:\.\d+)?)\s*만\s*원?",
        text,
    )
    if range_match:
        return int(Decimal(range_match.group(1)) * 10_000), int(Decimal(range_match.group(2)) * 10_000)

    min_match = re.search(r"(?:전월\s*(?:실적|이용금액)?|지난달|직전\s*1개월)[^\n]{0,30}?(\d+(?:\.\d+)?)\s*만\s*원?\s*이상", text)
    if min_match:
        return int(Decimal(min_match.group(1)) * 10_000), None

    return None


def infer_benefit_type(main_title: str | None, sub_title: str | None, detail: str | None = None) -> str | None:
    primary = "\n".join(part for part in [main_title or "", sub_title or ""] if part)
    fallback = detail or ""
    text = primary if primary.strip() else fallback

    if "캐시백" in text:
        return "CASHBACK"
    if any(keyword in text for keyword in ("청구할인", "결제일 할인", "결제일할인", "할인")):
        return "DISCOUNT"
    if any(keyword in text for keyword in ("마일리지", "마일", "포인트리", "M포인트", "마이신한포인트", "포인트", "적립", "리워즈", "MR")):
        return "MILEAGE"
    return None


def parse_rate(text: str | None) -> Decimal | None:
    clean_text = strip_exclusion_sections(text)
    for match in re.finditer(r"(\d+(?:\.\d+)?)\s*%", clean_text):
        value = Decimal(match.group(1)).quantize(RATE_SCALE, rounding=ROUND_HALF_UP)
        if value > 0:
            return value
    return None


def parse_flat_amount(text: str | None) -> int | None:
    clean_text = strip_exclusion_sections(text)
    reward_patterns = (
        r"(\d[\d,]*(?:\.\d+)?)\s*(천|만)\s*(?:마이신한포인트|M포인트|포인트리|포인트|마일리지|마일)\s*적립",
        r"(\d[\d,]*)\s*(?:마이신한포인트|M포인트|포인트리|포인트|마일리지|마일)\s*적립",
    )
    for pattern in reward_patterns:
        for match in re.finditer(pattern, clean_text):
            before = clean_text[max(0, match.start() - 16):match.start()]
            if any(keyword in before for keyword in ("연간", "분기", "누적", "보너스", "예 :")):
                continue
            if len(match.groups()) >= 2:
                unit = match.group(2)
                multiplier = 1_000 if unit == "천" else 10_000
                return int(Decimal(match.group(1).replace(",", "")) * multiplier)
            return int(match.group(1).replace(",", ""))

    patterns = (
        rf"({MONEY_PATTERN})\s*(?:[가-힣A-Za-z]+\s*){{0,3}}(?:할인|캐시백)",
        rf"(?:할인|캐시백)\s*(?:[가-힣A-Za-z]+\s*){{0,3}}({MONEY_PATTERN})",
    )
    for pattern in patterns:
        for match in re.finditer(pattern, clean_text):
            before = clean_text[max(0, match.start() - 12):match.start()]
            if any(keyword in before for keyword in ("한도", "최대", "이상", "까지")):
                continue
            amount = normalize_money(match.group(1))
            if amount:
                return amount
    return None


def parse_min_amount(text: str | None) -> int | None:
    clean_text = strip_exclusion_sections(text)
    period_usage_keywords = (
        "전월",
        "지난달",
        "직전",
        "말일까지",
        "이용실적",
        "실적",
        "본인, 가족",
        "가족카드",
        "합산",
        "전년도",
        "최근 3개월",
        "분기",
        "총 ",
        "연회비 청구 주기",
        "월 이용금액",
        "월 이용 금액",
        "당월 이용금액",
        "당월 이용 금액",
        "분기별 이용실적",
        "카드 사용등록일",
        "카드사용 등록일",
        "카드 사용 등록일",
    )
    strong_payment_keywords = (
        "건당",
        "건별",
        "1회",
        "결제 시",
        "결제시",
        "결제 건",
        "결제건",
        "결제금액",
        "결제 금액",
        "이용금액 기준 1회",
        "이용 금액 기준 1회",
        "이용금액 건당",
        "이용 금액 건당",
        "매출 건당",
        "보험료",
    )
    patterns = (
        rf"({MONEY_PATTERN})\s*이상[^\n]{{0,16}}(?:결제|이용|사용)",
        rf"(?:결제|이용|사용)[^\n]{{0,16}}({MONEY_PATTERN})\s*이상",
    )
    for pattern in patterns:
        for match in re.finditer(pattern, clean_text):
            line_start = clean_text.rfind("\n", 0, match.start()) + 1
            line_end = clean_text.find("\n", match.end())
            if line_end == -1:
                line_end = len(clean_text)
            line = clean_text[line_start:line_end]
            before = clean_text[max(0, match.start() - 24):match.start()]
            after = clean_text[match.end():min(len(clean_text), match.end() + 24)]
            context = f"{before}{match.group(0)}{after}"
            line_prefix = clean_text[line_start:match.start(1)]
            has_period_context = any(keyword in line or keyword in context for keyword in period_usage_keywords)
            if re.search(r"(?:^|[\s(])(?:월|매월)\s*$", line_prefix):
                has_period_context = True
            has_payment_context = any(keyword in line for keyword in strong_payment_keywords)
            if any(keyword in line for keyword in ("결제 건수", "결제건수", "건수별", "건수로 인정")):
                has_period_context = True
                has_payment_context = False
            if has_period_context and not has_payment_context:
                continue
            amount = normalize_money(match.group(1))
            if amount:
                return amount
    return None


def parse_day_condition(text: str | None) -> str:
    clean_text = strip_exclusion_sections(text)
    if any(keyword in clean_text for keyword in ("주말", "토요일", "일요일")):
        return "WEEKEND"
    if any(keyword in clean_text for keyword in ("평일", "주중")):
        return "WEEKDAY"
    return "ALL"


def _to_24h(period: str | None, hour: int) -> int:
    if period == "오후" and hour < 12:
        return hour + 12
    if period == "오전" and hour == 12:
        return 0
    return hour


def parse_time_condition(text: str | None) -> tuple[str | None, str | None]:
    clean_text = strip_exclusion_sections(text)
    match = re.search(
        r"(오전|오후)?\s*(\d{1,2})시(?:\s*(\d{1,2})분)?\s*(?:~|-|부터)\s*(오전|오후)?\s*(\d{1,2})시(?:\s*(\d{1,2})분)?",
        clean_text,
    )
    if not match:
        return None, None

    start_period, start_hour, start_minute, end_period, end_hour, end_minute = match.groups()
    start_hour_int = _to_24h(start_period, int(start_hour))
    end_hour_int = _to_24h(end_period, int(end_hour))
    start_minute_int = int(start_minute or 0)
    end_minute_int = int(end_minute or 0)
    return f"{start_hour_int:02d}:{start_minute_int:02d}:00", f"{end_hour_int:02d}:{end_minute_int:02d}:00"


def parse_limit_counts(text: str | None) -> dict[str, int | None]:
    clean_text = strip_exclusion_sections(text)
    result: dict[str, int | None] = {
        "daily_limit_count": None,
        "monthly_limit_count": None,
        "yearly_limit_count": None,
    }

    daily = re.search(r"(?:일|1일|하루)\s*(\d+)\s*회", clean_text)
    monthly = re.search(r"(?:월|월간|월\s*최대)\s*(\d+)\s*회", clean_text)
    yearly = re.search(r"(?:연|연간|년)\s*(\d+)\s*회", clean_text)
    if daily:
        result["daily_limit_count"] = int(daily.group(1))
    if monthly:
        result["monthly_limit_count"] = int(monthly.group(1))
    if yearly:
        result["yearly_limit_count"] = int(yearly.group(1))
    return result


def _amount_after(patterns: tuple[str, ...], text: str) -> int | None:
    for pattern in patterns:
        match = re.search(pattern, text)
        if match:
            return normalize_money(match.group(1))
    return None


def parse_limit_amounts(text: str | None) -> dict[str, int | None]:
    clean_text = strip_exclusion_sections(text)
    return {
        "max_benefit_per_use": _amount_after(
            (
                rf"(?:1회|건당|회당)[^\n]{{0,12}}?(?:최대|한도)[^\d]*({MONEY_PATTERN})",
                rf"(?:1회|건당|회당)[^\n]{{0,12}}?({MONEY_PATTERN})\s*(?:까지|한도)",
                rf"(?:최대)[^\n]{{0,8}}?({MONEY_PATTERN})[^\n]{{0,8}}?(?:까지|한도)",
            ),
            clean_text,
        ),
        "daily_limit_amount": _amount_after(
            (
                rf"(?:일|1일|하루)[^\n]{{0,12}}?(?:한도|최대)[^\d]*({MONEY_PATTERN})",
                rf"(?:일|1일|하루)[^\n]{{0,12}}?({MONEY_PATTERN})\s*(?:까지|한도)",
            ),
            clean_text,
        ),
        "monthly_limit_amount": _amount_after(
            (
                rf"(?:통합\s*)?월[^\n]{{0,18}}?(?:할인|적립|캐시백)?\s*한도[^\d]*({MONEY_PATTERN})",
                rf"(?:월\s*최대)[^\d]*({MONEY_PATTERN})",
                rf"월[^\n]{{0,12}}?({MONEY_PATTERN})\s*(?:까지|한도)",
                rf"({MONEY_PATTERN})\s*(?:까지|한도)[^\n]{{0,12}}?월",
            ),
            clean_text,
        ),
        "yearly_limit_amount": _amount_after(
            (
                rf"(?:연|연간|년)[^\n]{{0,12}}?(?:한도|최대)[^\d]*({MONEY_PATTERN})",
                rf"(?:연|연간|년)[^\n]{{0,12}}?({MONEY_PATTERN})\s*(?:까지|한도)",
            ),
            clean_text,
        ),
    }


def _unit_type(text: str, unit_word: str) -> str:
    if any(keyword.lower() in text.lower() for keyword in UNIT_REWARD_MILE_KEYWORDS) or "마일" in unit_word:
        return "MILE"
    return "POINT"


def parse_unit_reward_rate(text: str | None) -> dict[str, Any] | None:
    clean_text = strip_exclusion_sections(text)
    if not clean_text:
        return None
    if any(keyword in clean_text for keyword in UNIT_REWARD_EXCLUDED_KEYWORDS):
        return None

    pattern = (
        r"(\d[\d,]*(?:\.\d+)?)\s*(원|천원|만원)\s*당[^\d]{0,30}"
        r"(?:최대\s*)?(\d+(?:\.\d+)?)\s*(마일리지|마일|포인트리|M포인트|마이신한포인트|포인트|리워즈|MR)"
    )
    match = re.search(pattern, clean_text, flags=re.IGNORECASE)
    if not match:
        return None

    spend_value, spend_unit, reward_value, unit_word = match.groups()
    spend = normalize_money(f"{spend_value}{spend_unit}")
    reward = Decimal(reward_value)
    if not spend or reward <= 0:
        return None

    rate = (reward / Decimal(spend) * Decimal(100)).quantize(RATE_SCALE, rounding=ROUND_HALF_UP)
    if rate <= 0:
        return {
            "too_small": True,
            "spend": spend,
            "reward": reward,
            "unit_type": _unit_type(clean_text, unit_word),
            "rate": rate,
        }

    unit_type = _unit_type(clean_text, unit_word)
    return {
        "too_small": False,
        "spend": spend,
        "reward": reward,
        "unit_type": unit_type,
        "rate": rate,
        "raw": match.group(0),
        "tag": (
            f"[UNIT_REWARD type={unit_type} base_value=1 spend={spend} "
            f"reward={reward.normalize()} rate={format(rate, 'f')}] 원문: {match.group(0)}"
        ),
    }


def _parse_range_tiers(text: str) -> list[tuple[int, int | None, int]]:
    tiers: list[tuple[int, int | None, int]] = []
    range_pattern = (
        rf"(\d+(?:\.\d+)?)\s*만\s*원?\s*[~\-–]\s*(\d+(?:\.\d+)?)\s*만\s*원?"
        rf"[^\n:：]{{0,20}}[:：]?\s*({MONEY_PATTERN})"
    )
    for match in re.finditer(range_pattern, text):
        min_usage = int(Decimal(match.group(1)) * 10_000)
        max_usage = int(Decimal(match.group(2)) * 10_000)
        amount = normalize_money(match.group(3))
        if amount:
            tiers.append((min_usage, max_usage, amount))

    min_pattern = (
        rf"(\d+(?:\.\d+)?)\s*만\s*원?\s*이상"
        rf"[^\n:：]{{0,20}}[:：]?\s*({MONEY_PATTERN})"
    )
    for match in re.finditer(min_pattern, text):
        min_usage = int(Decimal(match.group(1)) * 10_000)
        amount = normalize_money(match.group(2))
        if amount and not any(existing[0] == min_usage for existing in tiers):
            tiers.append((min_usage, None, amount))

    return sorted(tiers, key=lambda item: item[0])


def parse_tiers(card_before_month: str | None, benefit_text: str | None) -> list[dict[str, Any]]:
    clean_text = strip_exclusion_sections(benefit_text)
    unit_reward = parse_unit_reward_rate(clean_text)
    rate = None if unit_reward and unit_reward.get("too_small") else (unit_reward or {}).get("rate")
    flat_amount = None
    tier_desc_parts: list[str] = []

    if unit_reward and unit_reward.get("too_small"):
        return []
    if unit_reward:
        tier_desc_parts.append(unit_reward["tag"])

    if rate is None:
        rate = parse_rate(clean_text)
    if rate is None:
        flat_amount = parse_flat_amount(clean_text)

    if rate is None and flat_amount is None:
        return []
    if rate is not None and not (Decimal("0") < rate < Decimal("100")):
        return []

    usage = parse_previous_month_usage(clean_text) or parse_previous_month_usage(card_before_month) or (0, None)
    limit_counts = parse_limit_counts(clean_text)
    limit_amounts = parse_limit_amounts(clean_text)
    range_tiers = _parse_range_tiers(clean_text)

    base_tier = {
        "rate": rate,
        "flat_amount": flat_amount,
        **limit_counts,
        **limit_amounts,
    }

    if tier_desc_parts:
        tier_desc_parts.append(f"전체 원문: {normalize_spaces(clean_text)}")
    tier_desc = " | ".join(tier_desc_parts) if tier_desc_parts else normalize_spaces(clean_text)

    if range_tiers and rate is not None:
        tiers = []
        for min_usage, max_usage, monthly_limit in range_tiers:
            tiers.append(
                {
                    **base_tier,
                    "min_prev_month_usage": min_usage,
                    "max_prev_month_usage": max_usage,
                    "monthly_limit_amount": monthly_limit,
                    "tier_desc": tier_desc,
                }
            )
        return tiers

    return [
        {
            **base_tier,
            "min_prev_month_usage": usage[0] if usage[0] is not None else 0,
            "max_prev_month_usage": usage[1],
            "tier_desc": tier_desc,
        }
    ]


def split_representative_line(sub_title: str | None, detail: str | None) -> tuple[str, bool, str]:
    lines = [line.strip() for line in (sub_title or "").splitlines() if line.strip()]
    if not lines:
        return sub_title or "", False, sub_title or ""

    if len(lines) == 1:
        return lines[0], False, lines[0]

    for line in lines:
        if infer_benefit_type("", line, "") and (parse_rate(line) is not None or parse_flat_amount(line) is not None or parse_unit_reward_rate(line)):
            rest = [item for item in lines if item != line]
            return line, True, "\n".join([line, *rest])
    return lines[0], True, "\n".join(lines)


def truncate_text(text: str | None, max_length: int) -> tuple[str | None, bool, int]:
    if text is None:
        return None, False, 0
    length = len(text)
    if length <= max_length:
        return text, False, length
    return text[:max_length], True, length
