"""
card_ids.json의 카드고릴라 card_id를 기준으로 카드 상세 원문 데이터를 수집한다.

이 스크립트는 DB 파싱 전 단계까지만 담당한다. card_product/card_benefit/card_benefit_tier
INSERT SQL 생성은 별도 파서에서 처리한다.
"""

import json
import time
from pathlib import Path

from selenium import webdriver
from selenium.common.exceptions import (
    ElementClickInterceptedException,
    NoSuchElementException,
    StaleElementReferenceException,
    TimeoutException,
)
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By
from selenium.webdriver.remote.webelement import WebElement
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.support.ui import WebDriverWait


BASE_URL = "https://www.card-gorilla.com"
DETAIL_URL = f"{BASE_URL}/card/detail/{{card_id}}"

SCRIPT_DIR = Path(__file__).resolve().parent
IDS_FILE = SCRIPT_DIR / "card_ids.json"
OUTPUT_FILE = SCRIPT_DIR / "card_gorilla_cards.json"


def make_driver() -> webdriver.Chrome:
    """상세 혜택 아코디언 클릭이 필요하므로 실제 Chrome 브라우저를 사용한다."""
    options = Options()
    options.add_argument("--headless=new")
    options.add_argument("--no-sandbox")
    options.add_argument("--disable-dev-shm-usage")
    options.add_argument("--disable-blink-features=AutomationControlled")
    options.add_argument("--window-size=1280,2400")
    options.add_argument(
        "user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
    )

    driver = webdriver.Chrome(options=options)
    driver.set_page_load_timeout(40)
    return driver


def text_or_empty(parent: WebElement, selector: str) -> str:
    """선택 요소가 없을 때도 상세 크롤링 전체가 중단되지 않도록 빈 문자열을 반환한다."""
    try:
        return parent.find_element(By.CSS_SELECTOR, selector).text.strip()
    except NoSuchElementException:
        return ""


def click_accordion(driver: webdriver.Chrome, element: WebElement) -> bool:
    """일반 클릭이 막히는 아코디언은 JS 클릭으로 한 번 더 시도한다."""
    try:
        driver.execute_script("arguments[0].scrollIntoView({block:'center'});", element)
        time.sleep(0.2)
        element.click()
        return True
    except (ElementClickInterceptedException, StaleElementReferenceException):
        try:
            driver.execute_script("arguments[0].click();", element)
            return True
        except Exception:
            return False
    except Exception:
        return False


def activate_lazy_content(driver: webdriver.Chrome) -> None:
    """상세 페이지 하단 lazy 영역을 렌더링하기 위해 끝까지 스크롤한 뒤 상단으로 복귀한다."""
    last_height = driver.execute_script("return document.body.scrollHeight")

    for _ in range(5):
        driver.execute_script("window.scrollTo(0, document.body.scrollHeight);")
        time.sleep(0.7)

        new_height = driver.execute_script("return document.body.scrollHeight")
        if new_height == last_height:
            break
        last_height = new_height

    driver.execute_script("window.scrollTo(0, 0);")
    time.sleep(0.4)


def extract_card_top(driver: webdriver.Chrome) -> dict:
    """card_product 매핑에 필요한 카드명, 카드사, 이미지 URL을 수집한다."""
    card_top = driver.find_element(By.CSS_SELECTOR, ".card_top")
    name = text_or_empty(card_top, "strong")
    image_url = ""

    try:
        image_url = card_top.find_element(By.CSS_SELECTOR, "img").get_attribute("src") or ""
    except NoSuchElementException:
        pass

    corp = ""
    for selector in ["p.brand", ".brand", "p em", "p i", "p span", "p"]:
        candidate = text_or_empty(card_top, selector)
        if candidate and candidate != name and len(candidate) < 30:
            corp = candidate
            break

    return {"name": name, "corp": corp, "image_url": image_url}


def extract_fee_and_performance(driver: webdriver.Chrome) -> dict:
    """연회비와 전월실적 원문을 보존해 이후 파서에서 숫자 조건으로 변환할 수 있게 한다."""
    try:
        bnf2 = driver.find_element(By.CSS_SELECTOR, "div.bnf2")
    except NoSuchElementException:
        return {"fee": "", "before_month": ""}

    fee = text_or_empty(bnf2, "dd.in_out")
    before_month = text_or_empty(bnf2, "dl:nth-child(2)")

    if not fee and not before_month and "연회비" in bnf2.text:
        fee = bnf2.text.strip()

    return {"fee": fee, "before_month": before_month}


def extract_main_benefits(driver: webdriver.Chrome) -> list[str]:
    """상세 혜택 파싱 실패에 대비해 카드고릴라가 노출하는 주요 혜택 요약도 함께 저장한다."""
    benefits: list[str] = []

    for selector in ["div.bnf1 li", "article.bnf li", ".bnf1 .lst li"]:
        for item in driver.find_elements(By.CSS_SELECTOR, selector):
            text = item.text.strip()
            if text and text not in benefits:
                benefits.append(text)
        if benefits:
            break

    return benefits


def extract_detail_benefits(driver: webdriver.Chrome) -> list[dict]:
    """혜택 아코디언을 순서대로 열어 card_benefit 파싱에 사용할 원문 텍스트를 수집한다."""
    try:
        bene_area = driver.find_element(By.CSS_SELECTOR, "div.bene_area")
    except NoSuchElementException:
        return []

    driver.execute_script("arguments[0].scrollIntoView({block:'start'});", bene_area)
    time.sleep(0.4)

    benefits: list[dict] = []
    total = len(driver.find_elements(By.CSS_SELECTOR, "div.bene_area dl"))

    for idx in range(total):
        try:
            dl = driver.find_elements(By.CSS_SELECTOR, "div.bene_area dl")[idx]
        except (IndexError, StaleElementReferenceException):
            continue

        opened_by_click = idx != 0 and click_accordion(driver, dl)
        if opened_by_click:
            time.sleep(0.4)

        main_title = text_or_empty(dl, "dt p") or text_or_empty(dl, "dt")
        sub_title = text_or_empty(dl, "dt i")
        detail_lines = [
            item.text.strip()
            for item in dl.find_elements(By.CSS_SELECTOR, "dd div.in_box p, dd div.in_box li")
            if item.text.strip()
        ]

        if not detail_lines:
            detail_text = text_or_empty(dl, "dd")
            if detail_text:
                detail_lines = [detail_text]

        if main_title or detail_lines:
            benefits.append(
                {
                    "main_title": main_title,
                    "sub_title": sub_title,
                    "detail": "\n".join(detail_lines),
                }
            )

        if opened_by_click:
            click_accordion(driver, dl)
            time.sleep(0.2)

    return benefits


def get_card_detail(driver: webdriver.Chrome, card_ref: dict) -> dict | None:
    """카드고릴라 상세 페이지에서 시딩 파서가 사용할 원문 데이터를 수집한다."""
    card_id = card_ref["card_id"]
    url = DETAIL_URL.format(card_id=card_id)

    # SPA 캐시로 이전 상세 화면이 남는 경우가 있어 빈 페이지를 거쳐 강제로 다시 로드한다.
    driver.get("about:blank")
    time.sleep(0.2)
    driver.get(url)

    try:
        WebDriverWait(driver, 12).until(
            EC.presence_of_element_located((By.CSS_SELECTOR, ".card_top, div.bnf2"))
        )
    except TimeoutException:
        print(f"  [{card_id}] 페이지 없음/로딩 실패")
        return None

    if f"/card/detail/{card_id}" not in driver.current_url:
        print(f"  [{card_id}] URL 미스매치 (현재: {driver.current_url})")
        return None

    activate_lazy_content(driver)

    try:
        card_top = extract_card_top(driver)
    except NoSuchElementException:
        return None

    if not card_top["name"]:
        return None

    return {
        "card_id": card_id,
        "url": url,
        "card_type": card_ref.get("card_type", ""),
        "source_chart": card_ref.get("source_chart", ""),
        "source_month": card_ref.get("source_month", ""),
        **card_top,
        **extract_fee_and_performance(driver),
        "main_benefits": extract_main_benefits(driver),
        "benefits": extract_detail_benefits(driver),
    }


def load_card_refs(input_file: Path = IDS_FILE) -> list[dict]:
    """collect_card_ids.py가 만든 card_ids.json을 상세 크롤링 입력으로 사용한다."""
    if not input_file.exists():
        raise FileNotFoundError(f"{input_file} 파일이 없습니다. collect_card_ids.py를 먼저 실행하세요.")

    data = json.loads(input_file.read_text(encoding="utf-8"))
    if not isinstance(data, list) or not data:
        raise ValueError(f"{input_file}에 크롤링할 카드 목록이 없습니다.")

    return data


def crawl_card_details(
    card_refs: list[dict],
    output_file: Path = OUTPUT_FILE,
    delay_seconds: float = 1.0,
    save_every: int = 10,
) -> list[dict]:
    """상세 크롤링 결과를 주기적으로 저장해 중간 실패 시에도 수집분을 보존한다."""
    driver = make_driver()
    results: list[dict] = []

    try:
        for index, card_ref in enumerate(card_refs, 1):
            card_id = card_ref["card_id"]
            print(f"[{index}/{len(card_refs)}] card_id={card_id} ...", end=" ")

            try:
                detail = get_card_detail(driver, card_ref)
            except Exception as exc:
                print(f"\n  [exception] {exc}")
                detail = None

            if detail:
                results.append(detail)
                print(f"OK - {detail['name']} ({detail['corp']}), 혜택 {len(detail['benefits'])}개")
            else:
                print("skipped")

            if index % save_every == 0:
                output_file.write_text(
                    json.dumps(results, ensure_ascii=False, indent=2),
                    encoding="utf-8",
                )

            time.sleep(delay_seconds)
    finally:
        driver.quit()

    output_file.write_text(
        json.dumps(results, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    print(f"\n[DONE] {len(results)}개 카드 -> {output_file}")
    return results


if __name__ == "__main__":
    crawl_card_details(load_card_refs())
