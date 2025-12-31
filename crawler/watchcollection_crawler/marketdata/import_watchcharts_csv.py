import json
import re
import unicodedata
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from typing import Dict, Iterator, Optional, Tuple


@dataclass
class ParsedCSVRow:
    brand_name: str
    reference: str
    price_usd_cents: int
    volatility_pct: Optional[float]
    raw_line: str


def normalize_brand_name(name: str) -> str:
    normalized = unicodedata.normalize("NFKD", name)
    normalized = "".join(c for c in normalized if not unicodedata.combining(c))
    return normalized.lower().strip()


def parse_filename(filename: str) -> Tuple[str, date]:
    pattern = r"^(.+?)\s+(\d{4}-\d{2}-\d{2})(?:\s*\(\d+\))?\.csv$"
    match = re.match(pattern, filename)
    if not match:
        raise ValueError(f"Invalid filename format: {filename}")
    brand_name = match.group(1).strip()
    date_str = match.group(2)
    return brand_name, date.fromisoformat(date_str)


def parse_reference_cell(cell: str) -> Tuple[str, str]:
    cell = cell.strip()
    if not cell:
        raise ValueError("Empty reference cell")

    match = re.match(r"^(.+?)\s+(\S+)$", cell)
    if not match:
        raise ValueError(f"Cannot parse reference: {cell}")

    brand_name = match.group(1).strip()
    reference = match.group(2).strip()
    return brand_name, reference


def parse_price(price_str: str) -> int:
    price_str = price_str.strip().strip('"').strip("'")
    price_str = price_str.replace(",", "")

    if not price_str:
        raise ValueError("Empty price string")

    try:
        price_float = float(price_str)
        return int(price_float * 100)
    except ValueError:
        raise ValueError(f"Invalid price format: {price_str}")


def parse_volatility(vol_str: str) -> Optional[float]:
    vol_str = vol_str.strip()
    if not vol_str:
        return None

    vol_str = vol_str.rstrip("%")
    try:
        return float(vol_str)
    except ValueError:
        return None


def parse_csv_row(row: Dict[str, str]) -> ParsedCSVRow:
    ref_cell = row.get("Reference Number", "")
    price_cell = row.get("Market Price (USD)", "")
    vol_cell = row.get("Market Volatility", "")

    brand_name, reference = parse_reference_cell(ref_cell)
    price_cents = parse_price(price_cell)
    volatility = parse_volatility(vol_cell)

    raw_line = json.dumps(row)

    return ParsedCSVRow(
        brand_name=brand_name,
        reference=reference,
        price_usd_cents=price_cents,
        volatility_pct=volatility,
        raw_line=raw_line,
    )


def build_catalog_lookup(catalog_path: Path) -> Dict[Tuple[str, str], Tuple[str, str]]:
    with open(catalog_path, "r", encoding="utf-8") as f:
        catalog = json.load(f)

    lookup: Dict[Tuple[str, str], Tuple[str, str]] = {}

    for brand in catalog.get("brands", []):
        brand_name = brand.get("name", "")
        brand_slug = brand.get("id", "")

        if not brand_name or not brand_slug:
            continue

        normalized_brand = normalize_brand_name(brand_name)

        for model in brand.get("models", []):
            reference = model.get("reference", "")
            watchcharts_id = model.get("watchcharts_id", "")

            if not reference or not watchcharts_id:
                continue

            key = (normalized_brand, reference)
            lookup[key] = (watchcharts_id, brand_slug)

    return lookup


def iter_csv_files(csv_dir: Path) -> Iterator[Path]:
    csv_files = sorted(csv_dir.glob("*.csv"))
    for csv_file in csv_files:
        yield csv_file
