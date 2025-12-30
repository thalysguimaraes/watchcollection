import time
import re
import json
import asyncio
from datetime import datetime
from typing import Optional, Dict, Any, List, Iterable, Tuple
from urllib.parse import urlencode

import requests
from bs4 import BeautifulSoup

from watchcollection_crawler.brand_rules import (
    allow_name_reference,
    get_reference_patterns,
    normalize_reference,
    normalize_text,
)
from watchcollection_crawler.core.brightdata import BrightDataClient
from watchcollection_crawler.core.flaresolverr import FlareSolverrClient
from watchcollection_crawler.core.playwright_stealth import PlaywrightStealthClient

CHRONO24_BASE = "https://www.chrono24.com"
SIMILAR_PERFORMANCE_ID_RE = re.compile(r"vue-simular-product-performance-(\d+)")
META_DATA_RE = re.compile(r"window\.metaData\s*=\s*(\{.*?\});", re.DOTALL)
DEFAULT_USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/122.0.0.0 Safari/537.36"
)


def brand_to_slug(brand: str) -> str:
    slugs = {
        # Holy Trinity
        "patek philippe": "patekphilippe",
        "audemars piguet": "audemarspiguet",
        "vacheron constantin": "vacheronconstantin",
        # Ultra Luxury
        "richard mille": "richardmille",
        "f.p. journe": "fpjourne",
        "mb&f": "mbf",
        # Luxury
        "a. lange & söhne": "alangesoehne",
        "jaeger-lecoultre": "jaegerlecoultre",
        "breguet": "breguet",
        "hublot": "hublot",
        "ulysse nardin": "ulyssenardin",
        "chopard": "chopard",
        "girard-perregaux": "girardperregaux",
        "piaget": "piaget",
        "glashütte original": "glashuetteoriginal",
        # Premium
        "iwc schaffhausen": "iwc",
        "bell & ross": "bellross",
        "baume & mercier": "baumemercier",
        # Upper Mid
        "tag heuer": "tagheuer",
        "grand seiko": "grandseiko",
        "frederique constant": "frederiqueconstant",
        "maurice lacroix": "mauricelacroix",
        "rado": "rado",
        # Independent
        "h. moser & cie": "hmosercie",
        "nomos glashütte": "nomos",
        "junghans": "junghans",
        "montblanc": "montblanc",
        # Accessible
        "casio g-shock": "casio",
        "citizen": "citizen",
        "mido": "mido",
        "certina": "certina",
    }
    brand_lower = brand.lower()
    return slugs.get(brand_lower, brand_lower.replace(" ", "-").replace(".", ""))


def _get_http_session(http_session: Optional[requests.Session]) -> Tuple[requests.Session, bool]:
    if http_session:
        return http_session, False
    return requests.Session(), True


def _build_headers(extra_headers: Optional[dict]) -> dict:
    headers = {"User-Agent": DEFAULT_USER_AGENT}
    if extra_headers:
        headers.update(extra_headers)
    return headers


def _fetch_html(
    url: str,
    *,
    use_flaresolverr: bool,
    client: Optional[FlareSolverrClient],
    http_session: Optional[requests.Session],
    brightdata_client: Optional[BrightDataClient],
    extra_headers: Optional[dict],
    timeout: float = 30.0,
) -> str:
    headers = _build_headers(extra_headers)
    if brightdata_client:
        return brightdata_client.get(url, headers=headers, timeout=timeout)
    if use_flaresolverr:
        if not client:
            raise ValueError("FlareSolverr client is required")
        return client.get(url, headers=headers)
    session, should_close = _get_http_session(http_session)
    try:
        resp = session.get(url, headers=headers, timeout=timeout)
        return resp.text
    finally:
        if should_close:
            session.close()


def search_by_reference(
    brand: str,
    reference: str,
    limit: int = 10,
    use_flaresolverr: bool = True,
    brand_id: Optional[str] = None,
    client: Optional[FlareSolverrClient] = None,
    http_session: Optional[requests.Session] = None,
    brightdata_client: Optional[BrightDataClient] = None,
    page: Optional[int] = None,
    currency: Optional[str] = None,
) -> List[Dict]:
    """Search Chrono24 by brand and reference number (for photo crawler)."""
    results = []
    slug = brand_to_slug(brand)

    # Build reference query: keep alphanumerics when letters are present
    ref_query = reference
    if reference:
        cleaned = re.sub(r"[^A-Za-z0-9]+", "", reference)
        if re.search(r"[A-Za-z]", cleaned):
            ref_query = cleaned
        else:
            ref_match = re.search(r"(\d{4,6})", cleaned)
            ref_query = ref_match.group(1) if ref_match else cleaned

    params = {"query": ref_query}
    if page and page > 1:
        params["showpage"] = str(page)
    if currency:
        params["currencyId"] = currency
    url = f"{CHRONO24_BASE}/{slug}/index.htm?{urlencode(params)}"

    if brightdata_client:
        html = _fetch_html(
            url,
            use_flaresolverr=False,
            client=None,
            http_session=http_session,
            brightdata_client=brightdata_client,
            extra_headers=None,
        )
        soup = BeautifulSoup(html, "html.parser")
        results = parse_search_results(soup, brand_name=brand, brand_id=brand_id)
    elif use_flaresolverr:
        owns_client = False
        if client is None:
            client = FlareSolverrClient()
            client.create_session()
            owns_client = True
        else:
            client.ensure_session()
        try:
            html = _fetch_html(
                url,
                use_flaresolverr=True,
                client=client,
                http_session=http_session,
                brightdata_client=None,
                extra_headers=None,
            )
            soup = BeautifulSoup(html, "html.parser")
            results = parse_search_results(soup, brand_name=brand, brand_id=brand_id)
        finally:
            if owns_client:
                client.destroy_session()
    else:
        html = _fetch_html(
            url,
            use_flaresolverr=False,
            client=None,
            http_session=http_session,
            brightdata_client=None,
            extra_headers=None,
        )
        soup = BeautifulSoup(html, "html.parser")
        results = parse_search_results(soup, brand_name=brand, brand_id=brand_id)

    return results[:limit]


def search_chrono24(
    brand: str,
    limit: int = 50,
    use_flaresolverr: bool = True,
    brand_id: Optional[str] = None,
    client: Optional[FlareSolverrClient] = None,
    http_session: Optional[requests.Session] = None,
    brightdata_client: Optional[BrightDataClient] = None,
) -> List[Dict]:
    results = []
    slug = brand_to_slug(brand)
    page = 1

    if brightdata_client:
        while len(results) < limit:
            url = f"{CHRONO24_BASE}/{slug}/index.htm?showpage={page}&sortorder=5"
            html = _fetch_html(
                url,
                use_flaresolverr=False,
                client=None,
                http_session=http_session,
                brightdata_client=brightdata_client,
                extra_headers=None,
            )
            soup = BeautifulSoup(html, "html.parser")
            page_results = parse_search_results(soup, brand_name=brand, brand_id=brand_id)
            if not page_results:
                break
            results.extend(page_results)
            page += 1
            time.sleep(1)
    elif use_flaresolverr:
        owns_client = False
        if client is None:
            client = FlareSolverrClient()
            client.create_session()
            owns_client = True
        else:
            client.ensure_session()
        try:
            while len(results) < limit:
                url = f"{CHRONO24_BASE}/{slug}/index.htm?showpage={page}&sortorder=5"
                html = _fetch_html(
                    url,
                    use_flaresolverr=True,
                    client=client,
                    http_session=http_session,
                    brightdata_client=None,
                    extra_headers=None,
                )
                soup = BeautifulSoup(html, "html.parser")
                page_results = parse_search_results(soup, brand_name=brand, brand_id=brand_id)
                if not page_results:
                    break
                results.extend(page_results)
                page += 1
                time.sleep(1)
        finally:
            if owns_client:
                client.destroy_session()
    else:
        while len(results) < limit:
            url = f"{CHRONO24_BASE}/{slug}/index.htm?showpage={page}&sortorder=5"
            html = _fetch_html(
                url,
                use_flaresolverr=False,
                client=None,
                http_session=http_session,
                brightdata_client=None,
                extra_headers=None,
            )
            soup = BeautifulSoup(html, "html.parser")
            page_results = parse_search_results(soup, brand_name=brand, brand_id=brand_id)
            if not page_results:
                break
            results.extend(page_results)
            page += 1
            time.sleep(1)

    return results[:limit]


def _is_year_reference(candidate: str) -> bool:
    if not candidate or not candidate.isdigit():
        return False
    year = int(candidate)
    return 1800 <= year <= 2030


def _extract_reference(text: str, brand_patterns: List[re.Pattern], brand_id: Optional[str]) -> Optional[str]:
    if not text:
        return None
    normalized = text
    normalized = normalized.replace("\u2010", "-").replace("\u2011", "-").replace("\u2012", "-")
    normalized = normalized.replace("\u2013", "-").replace("\u2014", "-")
    normalized = re.sub(r"\bref\.?\s*", "", normalized, flags=re.IGNORECASE)
    if brand_patterns:
        for pattern in brand_patterns:
            match = pattern.search(normalized)
            if match:
                reference = match.group(1) if match.groups() else match.group(0)
                return normalize_reference(reference.strip(), brand_id)

    ref_match = re.search(r'\b(\d{5,6}[A-Z]{0,4}(?:[.\-/][A-Z0-9]{1,10})*)\b', normalized)
    if not ref_match:
        # Tudor-style refs like 7941A1A0RU (4 digits + alphanumerics)
        ref_match = re.search(r'\b(\d{4}[A-Z0-9]{4,})\b', normalized, re.IGNORECASE)
    if not ref_match:
        ref_match = re.search(r'\b(\d{4}[A-Z]{1,4}(?:[.\-/][A-Z0-9]{1,10})*)\b', normalized)
        if not ref_match:
            ref_match = re.search(r'\b(\d{4})\b', normalized)
            if ref_match and _is_year_reference(ref_match.group(1)):
                ref_match = None
    if ref_match:
        return normalize_reference(ref_match.group(1), brand_id)
    return None


def _clean_name_reference(text: str) -> str:
    if not text:
        return ""
    cleaned = re.split(r'\s*[-–]\s*(?:New|Full|Complete|Box|Papers)', text)[0].strip()
    cleaned = re.sub(r'\b(?:Full Set|Box(?:es)?|Papers|Unworn|Unused|New|Neu|Limited)\b', '', cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r'\s{2,}', ' ', cleaned).strip()
    cleaned = re.sub(r'\b(19|20)\d{2}\b$', '', cleaned).strip()
    return cleaned


def parse_search_results(
    soup: BeautifulSoup,
    brand_name: Optional[str] = None,
    brand_id: Optional[str] = None,
) -> List[Dict]:
    results = []
    listings = soup.select(".wt-search-result, .wt-listing-item")
    brand_patterns = get_reference_patterns(brand_id)
    normalized_brand = normalize_text(brand_name) if brand_name else None
    allow_name_fallback = allow_name_reference(brand_id)

    for listing in listings:
        try:
            item = {}

            link = listing.select_one("a[href*='--id']")
            if link:
                href = link.get("href", "")
                item["url"] = CHRONO24_BASE + href if href.startswith("/") else href

            texts = [t.strip() for t in listing.stripped_strings if len(t.strip()) > 2]
            texts = [t for t in texts if not t.startswith("Go to slide")]

            model_name = None
            reference = None
            price = None

            for text in texts:
                if text in ["Popular", "Top seller", "New"]:
                    continue
                if re.match(r'^[\$€£]\s*[\d,]+', text):
                    price = text
                    continue
                if "shipping" in text.lower():
                    continue
                if not model_name:
                    model_name = text
                    reference = _extract_reference(model_name, brand_patterns, brand_id) or reference
                elif not reference:
                    reference = _extract_reference(text, brand_patterns, brand_id) or reference

            # Fallback: use second text element as reference for name-based brands
            # (F.P. Journe, etc. that use model names instead of refs)
            if not reference and allow_name_fallback and len(texts) >= 2:
                second_text = texts[1] if len(texts) > 1 else ""
                # Only use as ref if it's not a price and not too long
                if second_text and not re.match(r'^[\$€£]', second_text) and len(second_text) < 80:
                    clean_ref = _clean_name_reference(second_text)
                    if clean_ref and len(clean_ref) >= 3:
                        clean_ref_normalized = normalize_text(clean_ref)
                        if normalized_brand and clean_ref_normalized == normalized_brand:
                            clean_ref = ""
                    if clean_ref:
                        reference = clean_ref

            if reference:
                reference = normalize_reference(reference.strip(), brand_id)

            item["title"] = model_name or ""
            item["manufacturer"] = brand_name or (model_name.split()[0] if model_name else "")
            item["reference_number"] = reference
            item["price"] = price

            imgs = listing.select("img")
            image_urls = []
            for img in imgs:
                src = img.get("data-src") or img.get("src", "")
                if src and not src.startswith("data:") and "chrono24" in src:
                    image_urls.append(src)
            item["image_urls"] = list(set(image_urls))[:5]

            if item.get("title"):
                results.append(item)

        except Exception:
            continue

    return results


def get_watch_details(
    url: str,
    use_flaresolverr: bool = True,
    client: Optional[FlareSolverrClient] = None,
    http_session: Optional[requests.Session] = None,
    brightdata_client: Optional[BrightDataClient] = None,
) -> Dict[str, Any]:
    if brightdata_client:
        html = _fetch_html(
            url,
            use_flaresolverr=False,
            client=None,
            http_session=http_session,
            brightdata_client=brightdata_client,
            extra_headers=None,
        )
        soup = BeautifulSoup(html, "html.parser")
    elif use_flaresolverr:
        owns_client = False
        if client is None:
            client = FlareSolverrClient()
            client.create_session()
            owns_client = True
        else:
            client.ensure_session()
        try:
            html = _fetch_html(
                url,
                use_flaresolverr=True,
                client=client,
                http_session=http_session,
                brightdata_client=None,
                extra_headers=None,
            )
            soup = BeautifulSoup(html, "html.parser")
        finally:
            if owns_client:
                client.destroy_session()
    else:
        html = _fetch_html(
            url,
            use_flaresolverr=False,
            client=None,
            http_session=http_session,
            brightdata_client=None,
            extra_headers=None,
        )
        soup = BeautifulSoup(html, "html.parser")

    return parse_watch_details(soup)


def _normalize_label(label: str) -> str:
    return re.sub(r"[^a-z0-9]+", " ", label.lower()).strip()


def _map_spec_label(label: str) -> Optional[str]:
    if not label:
        return None
    normalized = _normalize_label(label)
    if not normalized:
        return None
    if "case diameter" in normalized or normalized in {"diameter", "case size"}:
        return "case_diameter"
    if "water resistance" in normalized or "waterproof" in normalized:
        return "water_resistance"
    if "case material" in normalized:
        return "case_material"
    if normalized == "material":
        return "case_material"
    if "material" in normalized and any(term in normalized for term in ["bracelet", "strap", "band"]):
        return None
    if "movement" in normalized:
        return "movement"
    if "caliber" in normalized or "calibre" in normalized:
        return "caliber"
    if "year of production" in normalized or "production year" in normalized or normalized == "year":
        return "year_of_production"
    if normalized in {"reference", "reference number", "reference no", "reference no.", "ref"}:
        return "reference_number"
    return None


def _maybe_set(details: Dict[str, Any], key: str, value: Any) -> None:
    if value is None:
        return
    if isinstance(value, str):
        value = value.strip()
        if not value:
            return
    if key not in details or not details[key]:
        details[key] = value


def _coerce_scalar(value: Any, preferred_keys: Optional[List[str]] = None) -> Optional[str]:
    if value is None:
        return None
    if isinstance(value, str):
        return value.strip() or None
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, list):
        for item in value:
            scalar = _coerce_scalar(item, preferred_keys=preferred_keys)
            if scalar:
                return scalar
        return None
    if isinstance(value, dict):
        keys_to_try = list(preferred_keys or [])
        keys_to_try += ["value", "text", "name", "displayName", "label"]
        for key in keys_to_try:
            if key in value and value[key]:
                return _coerce_scalar(value[key])
        return json.dumps(value, ensure_ascii=True)
    return str(value)


def _extract_image_urls(value: Any) -> List[str]:
    urls = []
    if isinstance(value, str):
        if value.startswith("http"):
            urls.append(value)
    elif isinstance(value, dict):
        for key in ("url", "src", "large", "medium", "small", "imageUrl", "image_url"):
            url = value.get(key)
            if isinstance(url, str) and url.startswith("http"):
                urls.append(url)
    elif isinstance(value, list):
        for item in value:
            urls.extend(_extract_image_urls(item))
    return urls


def _merge_image_urls(details: Dict[str, Any], urls: List[str]) -> None:
    if not urls:
        return
    deduped = []
    for url in urls:
        if url and url not in deduped:
            deduped.append(url)
    existing = details.get("image_urls") or []
    if isinstance(existing, list):
        for url in existing:
            if url and url not in deduped:
                deduped.append(url)
    details["image_urls"] = deduped


def _iter_dicts(obj: Any) -> Iterable[Dict[str, Any]]:
    if isinstance(obj, dict):
        yield obj
        for value in obj.values():
            yield from _iter_dicts(value)
    elif isinstance(obj, list):
        for item in obj:
            yield from _iter_dicts(item)


def _collect_spec_items(obj: Any) -> List[Tuple[str, Any]]:
    items: List[Tuple[str, Any]] = []
    for data in _iter_dicts(obj):
        label = data.get("label") or data.get("name") or data.get("key") or data.get("title")
        value = data.get("value") or data.get("text") or data.get("displayValue")
        if isinstance(label, str) and label.strip() and value not in (None, ""):
            items.append((label, value))
    return items


def _extract_json_payloads(soup: BeautifulSoup) -> List[Any]:
    payloads = []

    script = soup.select_one("script#__NEXT_DATA__")
    if script and script.string:
        try:
            payloads.append(json.loads(script.string))
        except json.JSONDecodeError:
            pass

    for script in soup.find_all("script", attrs={"type": "application/ld+json"}):
        if not script.string:
            continue
        try:
            payloads.append(json.loads(script.string))
        except json.JSONDecodeError:
            continue

    return payloads


def _extract_details_from_payload(payload: Any, details: Dict[str, Any]) -> None:
    if not payload:
        return

    spec_items = _collect_spec_items(payload)
    for label, value in spec_items:
        key = _map_spec_label(label)
        if not key:
            continue
        if isinstance(value, (dict, list)):
            value = json.dumps(value, ensure_ascii=True)
        _maybe_set(details, key, value)

    key_aliases = {
        "case_diameter": ["case_diameter", "caseDiameter", "caseDiameterMm", "diameter", "caseSize"],
        "case_material": ["case_material", "caseMaterial", "caseMaterialName", "material"],
        "water_resistance": ["water_resistance", "waterResistance", "waterResistanceMeters", "waterResistanceValue", "waterproof"],
        "movement": ["movement", "movementType", "movement_type", "movementTypeName", "movementTypeDisplay"],
        "caliber": ["caliber", "calibre", "movementCaliber", "movement_caliber", "caliberName"],
        "year_of_production": ["year_of_production", "yearOfProduction", "productionYear", "productionYearFrom", "yearOfManufacture"],
        "reference_number": ["reference_number", "referenceNumber", "reference", "referenceNo", "modelNumber"],
        "title": ["title", "model", "modelName", "name", "watchName", "productName"],
        "image_urls": ["image_urls", "imageUrls", "images", "image", "imageUrl", "gallery"],
    }
    preferred_scalar_keys = {
        "case_diameter": ["value", "diameter", "size"],
        "case_material": ["name", "material", "displayName"],
        "water_resistance": ["value", "text"],
        "movement": ["name", "type", "movementType", "displayName"],
        "caliber": ["name", "baseCaliber", "caliber", "reference"],
        "year_of_production": ["year", "value", "text"],
        "reference_number": ["reference", "value", "number"],
        "title": ["name", "value", "text"],
    }

    for data in _iter_dicts(payload):
        lowered = {str(key).lower(): key for key in data.keys()}
        for canonical, aliases in key_aliases.items():
            for alias in aliases:
                alias_key = lowered.get(alias.lower())
                if not alias_key:
                    continue
                value = data.get(alias_key)
                if value in (None, ""):
                    continue
                if canonical == "image_urls":
                    urls = _extract_image_urls(value)
                    urls = [url for url in urls if "chrono24" in url]
                    _merge_image_urls(details, urls)
                else:
                    scalar = _coerce_scalar(value, preferred_keys=preferred_scalar_keys.get(canonical))
                    _maybe_set(details, canonical, scalar)


def _extract_html_spec_pairs(soup: BeautifulSoup) -> List[Tuple[str, str]]:
    pairs: List[Tuple[str, str]] = []

    for row in soup.select("table tr"):
        cells = row.find_all(["th", "td"])
        if len(cells) >= 2:
            label = cells[0].get_text(strip=True)
            value = cells[1].get_text(strip=True)
            if label and value:
                pairs.append((label, value))

    for item in soup.select(".specification-item"):
        label_el = item.select_one(".spec-label, .specification__label")
        value_el = item.select_one(".spec-value, .specification__value")
        if label_el and value_el:
            label = label_el.get_text(strip=True)
            value = value_el.get_text(strip=True)
            if label and value:
                pairs.append((label, value))

    for dl in soup.select("dl"):
        for dt in dl.find_all("dt"):
            dd = dt.find_next_sibling("dd")
            if dd:
                label = dt.get_text(strip=True)
                value = dd.get_text(strip=True)
                if label and value:
                    pairs.append((label, value))

    return pairs


def parse_watch_details(soup: BeautifulSoup) -> Dict[str, Any]:
    details = {}

    for payload in _extract_json_payloads(soup):
        _extract_details_from_payload(payload, details)

    for label, value in _extract_html_spec_pairs(soup):
        key = _map_spec_label(label)
        if key:
            _maybe_set(details, key, value)

    title = soup.select_one("h1")
    if title:
        details["title"] = title.get_text(strip=True)

    images = []
    for img in soup.select("img[src*='chrono24']"):
        src = img.get("data-src") or img.get("src", "")
        if src and not src.startswith("data:") and src not in images:
            images.append(src)
    _merge_image_urls(details, images[:10])

    return details


def _extract_meta_data(html: str) -> Optional[dict]:
    if not html:
        return None
    match = META_DATA_RE.search(html)
    if not match:
        return None
    try:
        return json.loads(match.group(1))
    except json.JSONDecodeError:
        return None


def _extract_similar_product_container(soup: BeautifulSoup) -> Dict[str, Any]:
    if soup is None:
        return {}
    node = soup.find(id=SIMILAR_PERFORMANCE_ID_RE)
    if not node:
        return {}
    watch_id = node.get("data-watch-id")
    product_id = node.get("data-product-id")
    return {
        "watch_id": int(watch_id) if watch_id and str(watch_id).isdigit() else None,
        "product_id": int(product_id) if product_id and str(product_id).isdigit() else None,
        "product_performance_page_id": node.get("data-product-performance-page-id"),
        "show_headline": (node.get("data-show-headline") or "").lower() == "true",
    }


def _extract_similar_product_meta(meta: Optional[dict], watch_id: Optional[int]) -> Optional[dict]:
    if not meta or not watch_id:
        return None
    data = meta.get("data") or {}
    return data.get(f"similarProduct-{watch_id}") or None


def _decode_json_response(text: str) -> Optional[dict]:
    if not text:
        return None
    raw = text.strip()
    if raw.startswith("<"):
        soup = BeautifulSoup(raw, "html.parser")
        raw = soup.get_text().strip()
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return None


def get_similar_product_context(
    url: str,
    use_flaresolverr: bool = True,
    client: Optional[FlareSolverrClient] = None,
    http_session: Optional[requests.Session] = None,
    extra_headers: Optional[dict] = None,
    brightdata_client: Optional[BrightDataClient] = None,
) -> Dict[str, Any]:
    if not url:
        return {}

    html = ""
    if brightdata_client:
        html = _fetch_html(
            url,
            use_flaresolverr=False,
            client=None,
            http_session=http_session,
            brightdata_client=brightdata_client,
            extra_headers=extra_headers,
        )
    elif use_flaresolverr:
        owns_client = False
        if client is None:
            client = FlareSolverrClient()
            client.create_session()
            owns_client = True
        else:
            client.ensure_session()
        try:
            html = _fetch_html(
                url,
                use_flaresolverr=True,
                client=client,
                http_session=http_session,
                brightdata_client=None,
                extra_headers=extra_headers,
            )
        finally:
            if owns_client:
                client.destroy_session()
    else:
        html = _fetch_html(
            url,
            use_flaresolverr=False,
            client=None,
            http_session=http_session,
            brightdata_client=None,
            extra_headers=extra_headers,
        )

    soup = BeautifulSoup(html, "html.parser")
    meta = _extract_meta_data(html) or {}
    container = _extract_similar_product_container(soup)
    watch_id = container.get("watch_id")
    similar_product = _extract_similar_product_meta(meta, watch_id)

    return {
        "url": url,
        "watch_id": watch_id,
        "product_id": container.get("product_id"),
        "product_performance_page_id": container.get("product_performance_page_id"),
        "show_headline": container.get("show_headline"),
        "similar_product": similar_product,
        "csrf_token": meta.get("csrfValue") or meta.get("csrf"),
        "currency": meta.get("currency"),
        "blocked": meta.get("blocked"),
        "meta": meta,
    }


def fetch_similar_product_chart(
    product_id: int,
    csrf_token: Optional[str],
    preferred_range: Optional[str] = "max",
    condition_new: bool = False,
    use_flaresolverr: bool = True,
    client: Optional[FlareSolverrClient] = None,
    http_session: Optional[requests.Session] = None,
    referer: Optional[str] = None,
    extra_headers: Optional[dict] = None,
    brightdata_client: Optional[BrightDataClient] = None,
) -> Optional[dict]:
    if not product_id:
        return None

    params = {
        "productId": product_id,
        "conditionNew": str(condition_new).lower(),
    }
    if preferred_range:
        params["preferredRange"] = preferred_range
    url = f"{CHRONO24_BASE}/api/watch-collection/get-product-chart-data.json?{urlencode(params)}"
    headers = {}
    if csrf_token:
        headers["x-csrf-token"] = csrf_token
    if referer:
        headers["Referer"] = referer
    if extra_headers:
        headers.update(extra_headers)

    if brightdata_client:
        raw = _fetch_html(
            url,
            use_flaresolverr=False,
            client=None,
            http_session=http_session,
            brightdata_client=brightdata_client,
            extra_headers=headers,
        )
    elif use_flaresolverr:
        owns_client = False
        if client is None:
            client = FlareSolverrClient()
            client.create_session()
            owns_client = True
        else:
            client.ensure_session()
        try:
            raw = _fetch_html(
                url,
                use_flaresolverr=True,
                client=client,
                http_session=http_session,
                brightdata_client=None,
                extra_headers=headers,
            )
        finally:
            if owns_client:
                client.destroy_session()
    else:
        raw = _fetch_html(
            url,
            use_flaresolverr=False,
            client=None,
            http_session=http_session,
            brightdata_client=None,
            extra_headers=headers,
        )

    return _decode_json_response(raw)


def get_similar_product_performance(
    url: str,
    preferred_range: Optional[str] = "max",
    condition_new: bool = False,
    use_flaresolverr: bool = True,
    client: Optional[FlareSolverrClient] = None,
    http_session: Optional[requests.Session] = None,
    extra_headers: Optional[dict] = None,
    brightdata_client: Optional[BrightDataClient] = None,
) -> Dict[str, Any]:
    context = get_similar_product_context(
        url,
        use_flaresolverr=use_flaresolverr,
        client=client,
        http_session=http_session,
        extra_headers=extra_headers,
        brightdata_client=brightdata_client,
    )

    chart_payload = None
    if context.get("product_id"):
        chart_payload = fetch_similar_product_chart(
            product_id=context["product_id"],
            csrf_token=context.get("csrf_token"),
            preferred_range=preferred_range,
            condition_new=condition_new,
            use_flaresolverr=use_flaresolverr,
            client=client,
            http_session=http_session,
            referer=url,
            extra_headers=extra_headers,
            brightdata_client=brightdata_client,
        )

    chart = None
    if isinstance(chart_payload, dict):
        chart = chart_payload.get("chart") or chart_payload.get("data", {}).get("chart")

    return {
        "context": context,
        "chart_payload": chart_payload,
        "chart": chart,
    }


def coerce_timestamp(value: Any) -> Optional[int]:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        ts = int(value)
        return ts // 1000 if ts > 10**11 else ts
    if isinstance(value, str):
        raw = value.strip()
        if raw.isdigit():
            ts = int(raw)
            return ts // 1000 if ts > 10**11 else ts
        try:
            if raw.endswith("Z"):
                raw = raw.replace("Z", "+00:00")
            dt = datetime.fromisoformat(raw)
            return int(dt.timestamp())
        except ValueError:
            return None
    return None


def _cookie_header_from_cookies(cookies: List[dict], domain_suffix: str = "chrono24.com") -> Optional[str]:
    if not cookies:
        return None
    pairs = []
    for cookie in cookies:
        domain = cookie.get("domain") or ""
        if domain_suffix not in domain:
            continue
        name = cookie.get("name")
        value = cookie.get("value")
        if not name or value is None or value == "":
            continue
        pairs.append(f"{name}={value}")
    return "; ".join(pairs) if pairs else None


async def _maybe_accept_cookies(page) -> None:
    selectors = [
        "button:has-text('Accept all')",
        "button:has-text('Accept')",
        "button:has-text('I agree')",
        "button:has-text('Allow all')",
        "button:has-text('Agree')",
        "[data-testid*='accept' i]",
        "[id*='accept' i]",
    ]
    for selector in selectors:
        try:
            locator = page.locator(selector)
            if await locator.count() > 0:
                await locator.first.click(timeout=1500)
                await page.wait_for_timeout(500)
                break
        except Exception:
            continue


async def _fill_first(page, selectors: List[str], value: str) -> bool:
    for selector in selectors:
        try:
            locator = page.locator(selector)
            if await locator.count() > 0:
                await locator.first.fill(value, timeout=3000)
                return True
        except Exception:
            continue
    return False


async def _click_first(page, selectors: List[str]) -> bool:
    for selector in selectors:
        try:
            locator = page.locator(selector)
            if await locator.count() > 0:
                await locator.first.click(timeout=3000)
                return True
        except Exception:
            continue
    return False


async def _playwright_login_and_get_cookie_header(
    email: str,
    password: str,
    headless: bool = True,
    timeout: float = 60.0,
    login_url: Optional[str] = None,
    manual: bool = False,
    channel: Optional[str] = None,
    user_data_dir: Optional[str] = None,
    use_stealth: bool = True,
) -> Optional[str]:
    login_url = login_url or f"{CHRONO24_BASE}/login"
    client = PlaywrightStealthClient(
        headless=headless,
        timeout=timeout,
        channel=channel,
        user_data_dir=user_data_dir,
        use_stealth=use_stealth,
    )
    try:
        await client.start()
        page = client.page
        if page is None:
            return None
        await page.goto(login_url, wait_until="domcontentloaded")
        try:
            content = await page.content()
            if "Page not found" in content or "page not found" in content or "404" in content:
                print("Login URL returned 404. Opening homepage for manual login.", flush=True)
                await page.goto(CHRONO24_BASE, wait_until="domcontentloaded")
        except Exception:
            pass
        await _maybe_accept_cookies(page)

        email_selectors = [
            "input[type='email']",
            "input[name='email']",
            "input[id*='email' i]",
            "input[name='username']",
            "input[id*='username' i]",
        ]
        password_selectors = [
            "input[type='password']",
            "input[name='password']",
            "input[id*='password' i]",
        ]
        submit_selectors = [
            "button[type='submit']",
            "input[type='submit']",
            "button:has-text('Log in')",
            "button:has-text('Login')",
            "button:has-text('Sign in')",
            "button:has-text('Anmelden')",
            "button:has-text('Entrar')",
            "button:has-text('Continuar')",
        ]

        if manual:
            print("Playwright opened Chrono24 login page.", flush=True)
            print("Complete login in the browser. Waiting up to 5 minutes for session cookies...", flush=True)
            max_wait = 300
        else:
            await _fill_first(page, email_selectors, email)
            await _fill_first(page, password_selectors, password)
            await _click_first(page, submit_selectors)
            max_wait = 30

        session_cookie_names = {"c24-user-session", "c24_access_token", "c24_user_id"}
        for i in range(max_wait):
            cookies = await client.cookies()
            names = {c.get("name") for c in cookies}
            found_session = names & session_cookie_names
            if found_session:
                print(f"Session cookie(s) found after {i+1}s: {found_session}", flush=True)
                return _cookie_header_from_cookies(cookies)
            if i > 0 and i % 30 == 0:
                print(f"Still waiting for login... ({i}s elapsed, cookies: {names})", flush=True)
            await page.wait_for_timeout(1000)

        print(f"No session cookie found within {max_wait}s timeout", flush=True)
        return None
    finally:
        await client.close()


def playwright_login_cookie_header(
    email: str,
    password: str,
    headless: bool = True,
    timeout: float = 60.0,
    login_url: Optional[str] = None,
    manual: bool = False,
    channel: Optional[str] = None,
    user_data_dir: Optional[str] = None,
    use_stealth: bool = True,
) -> Optional[str]:
    if not manual and (not email or not password):
        return None

    try:
        loop = asyncio.get_running_loop()
    except RuntimeError:
        loop = None

    if loop and loop.is_running():
        new_loop = asyncio.new_event_loop()
        try:
            asyncio.set_event_loop(new_loop)
            return new_loop.run_until_complete(
                _playwright_login_and_get_cookie_header(
                    email=email,
                    password=password,
                    headless=headless,
                    timeout=timeout,
                    login_url=login_url,
                    manual=manual,
                    channel=channel,
                    user_data_dir=user_data_dir,
                    use_stealth=use_stealth,
                )
            )
        finally:
            new_loop.close()
            asyncio.set_event_loop(loop)

    return asyncio.run(
        _playwright_login_and_get_cookie_header(
            email=email,
            password=password,
            headless=headless,
            timeout=timeout,
            login_url=login_url,
            manual=manual,
            channel=channel,
            user_data_dir=user_data_dir,
            use_stealth=use_stealth,
        )
    )
