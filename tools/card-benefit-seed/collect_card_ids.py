"""
카드고릴라 월간 신용/체크 TOP100 차트에서 상세 크롤링 대상 카드 ID를 수집한다.

수집한 card_id는 card_product.source_card_id에 저장할 카드고릴라 원천 ID로 사용한다.
"""

import json
import re
import time
from pathlib import Path

from bs4 import BeautifulSoup
from selenium import webdriver
from selenium.common.exceptions import TimeoutException
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.support.ui import WebDriverWait


BASE_URL = "https://www.card-gorilla.com"
CHART_URL = f"{BASE_URL}/chart/{{chart_path}}?term=monthly&date={{month}}"

SCRIPT_DIR = Path(__file__).resolve().parent
OUTPUT_FILE = SCRIPT_DIR / "card_ids.json"

CRAWL_MONTH = "2026-04-01"
CHARTS = [
    {"path": "top100", "name": "credit_top100", "card_type": "CREDIT"},
    {"path": "check100", "name": "check_top100", "card_type": "CHECK"},
]


def make_driver() -> webdriver.Chrome:
    """카드고릴라 차트가 JS로 렌더링되므로 실제 Chrome 브라우저를 사용한다."""
    options = Options()
    options.add_argument("--headless=new")
    options.add_argument("--no-sandbox")
    options.add_argument("--disable-dev-shm-usage")
    options.add_argument("--disable-blink-features=AutomationControlled")
    options.add_argument("--window-size=1280,2200")
    options.add_argument(
        "user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
    )

    driver = webdriver.Chrome(options=options)
    driver.set_page_load_timeout(40)
    return driver


def scroll_to_bottom(driver: webdriver.Chrome) -> None:
    """lazy loading으로 뒤늦게 붙는 카드 목록까지 확보하기 위해 하단까지 스크롤한다."""
    last_height = driver.execute_script("return document.body.scrollHeight")

    for _ in range(8):
        driver.execute_script("window.scrollTo(0, document.body.scrollHeight);")
        time.sleep(1.0)

        new_height = driver.execute_script("return document.body.scrollHeight")
        if new_height == last_height:
            break
        last_height = new_height


def extract_card_id(image_src: str) -> int | None:
    """카드 상세 링크 대신 이미지 URL에 포함된 카드고릴라 card_id를 추출한다."""
    match = re.search(r"/card/(\d+)/", image_src)
    return int(match.group(1)) if match else None


def parse_chart_items(html: str, chart: dict, month: str) -> list[dict]:
    """렌더링된 차트 HTML에서 카드 기본 정보와 원천 ID를 추출한다."""
    soup = BeautifulSoup(html, "html.parser")
    cards: list[dict] = []

    for item in soup.select("ul.rk_lst > li"):
        if "ad" in (item.get("class") or []):
            continue

        name_el = item.select_one(".card_name")
        image_el = item.select_one(".card_img img")
        if not name_el or not image_el:
            continue

        card_id = extract_card_id(image_el.get("src", ""))
        if card_id is None:
            continue

        corp_el = item.select_one(".corp_name span") or item.select_one(".corp_name")
        rank_el = item.select_one(".num")

        cards.append(
            {
                "card_id": card_id,
                "name": name_el.get_text(strip=True),
                "corp": corp_el.get_text(strip=True) if corp_el else "",
                "rank": rank_el.get_text(strip=True) if rank_el else "",
                "card_type": chart["card_type"],
                "source_chart": chart["name"],
                "source_month": month,
                "detail_url": f"{BASE_URL}/card/detail/{card_id}",
            }
        )

    return cards


def collect_chart_cards(driver: webdriver.Chrome, chart: dict, month: str) -> list[dict]:
    """카드고릴라의 특정 차트 페이지를 열고 카드 ID 목록을 수집한다."""
    url = CHART_URL.format(chart_path=chart["path"], month=month)
    print(f"\n=== {month} {chart['name']} ===")

    driver.get(url)
    try:
        WebDriverWait(driver, 20).until(
            EC.presence_of_element_located((By.CSS_SELECTOR, "ul.rk_lst > li"))
        )
    except TimeoutException:
        raise RuntimeError(f"{chart['name']} 차트 로딩 실패: {url}")

    scroll_to_bottom(driver)
    cards = parse_chart_items(driver.page_source, chart, month)
    print(f"{len(cards)}개 카드 수집")
    return cards


def collect_card_ids(month: str = CRAWL_MONTH, output_file: Path = OUTPUT_FILE) -> list[dict]:
    """신용/체크 차트를 순서대로 수집하고 카드고릴라 card_id 기준으로 중복 제거한다."""
    driver = make_driver()
    seen_card_ids: set[int] = set()
    merged_cards: list[dict] = []

    try:
        for chart in CHARTS:
            for card in collect_chart_cards(driver, chart, month):
                if card["card_id"] in seen_card_ids:
                    continue
                seen_card_ids.add(card["card_id"])
                merged_cards.append(card)
            time.sleep(2)
    finally:
        driver.quit()

    output_file.write_text(
        json.dumps(merged_cards, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    print(f"\n[DONE] 중복 제거 후 총 {len(merged_cards)}개 카드 -> {output_file}")
    return merged_cards


if __name__ == "__main__":
    collect_card_ids()
