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
        target = element.find_element(By.CSS_SELECTOR, "dt")
    except NoSuchElementException:
        target = element

    try:
        driver.execute_script("arguments[0].scrollIntoView({block:'center'});", target)
        time.sleep(0.2)
        target.click()
        return True
    except (ElementClickInterceptedException, StaleElementReferenceException):
        try:
            driver.execute_script("arguments[0].click();", target)
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


def wait_for_accordion_detail(driver: webdriver.Chrome, element: WebElement, timeout_seconds: float = 3.0) -> None:
    """아코디언 클릭 뒤 Vue가 dd를 렌더링할 시간을 준다."""
    try:
        WebDriverWait(driver, timeout_seconds).until(
            lambda _: len(element.find_elements(By.CSS_SELECTOR, "dd")) > 0
        )
    except TimeoutException:
        pass


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


def extract_table_context(driver: webdriver.Chrome, table: WebElement) -> str:
    """테이블 직전의 짧은 설명 문구를 함께 보존해 어떤 조건표인지 검수할 수 있게 한다."""
    context = driver.execute_script(
        """
        const table = arguments[0];
        const texts = [];
        let node = table.previousSibling;

        while (node && texts.length < 3) {
          if (node.nodeType === Node.ELEMENT_NODE) {
            const tag = node.tagName.toLowerCase();
            if (tag === 'table') {
              break;
            }
            const text = (node.innerText || node.textContent || '').trim();
            if (text) {
              texts.unshift(text);
            }
          } else if (node.nodeType === Node.TEXT_NODE) {
            const text = (node.textContent || '').trim();
            if (text) {
              texts.unshift(text);
            }
          }
          node = node.previousSibling;
        }

        return texts.join('\\n');
        """,
        table,
    )
    return str(context or "").strip()


def extract_table_rows(table: WebElement) -> tuple[list[str], list[list[str]]]:
    """HTML table의 헤더와 행 텍스트를 2차원 배열로 보존한다."""
    parsed_rows: list[tuple[list[str], bool]] = []

    for row in table.find_elements(By.CSS_SELECTOR, "tr"):
        cells = []
        has_header_cell = False
        for cell in row.find_elements(By.CSS_SELECTOR, "th, td"):
            text = cell.text.strip()
            if not text:
                continue
            cells.append(text)
            if cell.tag_name.lower() == "th":
                has_header_cell = True
        if cells:
            parsed_rows.append((cells, has_header_cell))

    if not parsed_rows:
        return [], []

    first_row, first_is_header = parsed_rows[0]
    header_markers = {"구분", "할인 대상", "서비스", "내용", "총 연회비", "기본 연회비", "제휴 연회비"}
    looks_like_header = any(cell in header_markers for cell in first_row)
    looks_like_amount_band_header = len(parsed_rows) == 2 and all("이상" in cell or "미만" in cell for cell in first_row)

    if first_is_header or looks_like_header or looks_like_amount_band_header:
        return first_row, [row for row, _ in parsed_rows[1:]]
    return [], [row for row, _ in parsed_rows]


def extract_detail_tables(driver: webdriver.Chrome, dl: WebElement) -> list[dict]:
    """혜택 상세 내 표를 JSON에 보존한다."""
    tables: list[dict] = []

    for index, table in enumerate(dl.find_elements(By.CSS_SELECTOR, "dd div.in_box table, dd table"), start=1):
        headers, rows = extract_table_rows(table)
        if not headers and not rows:
            continue

        tables.append(
            {
                "index": index,
                "context": extract_table_context(driver, table),
                "headers": headers,
                "rows": rows,
                "text": table.text.strip(),
            }
        )

    return tables


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

        opened_by_click = click_accordion(driver, dl)
        if opened_by_click:
            wait_for_accordion_detail(driver, dl)

        main_title = text_or_empty(dl, "dt p") or text_or_empty(dl, "dt")
        sub_title = text_or_empty(dl, "dt i")
        tables = extract_detail_tables(driver, dl)
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
                    "tables": tables,
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
