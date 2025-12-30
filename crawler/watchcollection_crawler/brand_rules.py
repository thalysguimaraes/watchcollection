import re
import unicodedata
from typing import Dict, List, Optional, Pattern

BRAND_RULES: Dict[str, Dict[str, object]] = {
    "a_lange_sohne": {
        "drop_leading_tokens": 1,
        "reference_patterns": [r"\b(\d{3}\.\d{3})\b"],
        "detail_fetch": True,
        "strict_reference_patterns": True,
    },
    "richard_mille": {
        "reference_patterns": [r"\b(RM\s?\d{2,4}(?:-\d{2,3})?(?:\s?[A-Z]{2,6})?)\b"],
        "detail_fetch": True,
        "strict_reference_patterns": True,
    },
    "h_moser": {
        "reference_patterns": [r"\b(\d{4}-\d{4}(?:/[A-Z0-9]+)?)\b"],
        "strict_reference_patterns": True,
    },
    "mb_and_f": {
        "reference_patterns": [r"\b(M\.A\.D\s?\d{0,2}|HM\d{1,2}|LM\d{1,2}|LMX|HMX)\b"],
        "detail_fetch": True,
        "strict_reference_patterns": True,
    },
    "fp_journe": {
        "allow_name_reference": True,
        "detail_fetch": True,
    },
    "vacheron_constantin": {
        "detail_fetch": True,
    },
    "rolex": {
        "detail_fetch": True,
    },
    "jaeger_lecoultre": {
        "reference_patterns": [
            r"\b(Q\d{6,7})\b",
            r"\b(\d{3}\.\d{3}\.\d{3}[A-Z]?)\b",
        ],
        "detail_fetch": True,
    },
    "hublot": {
        "reference_patterns": [
            r"\b(\d{3}\.[A-Z0-9]{2,}\.[A-Z0-9]{2,}\.[A-Z0-9]{2,})\b",
            r"\b(\d{3}\.[A-Z0-9]{2,}\.[A-Z0-9]{2,})\b",
        ],
        "detail_fetch": True,
    },
    "ulysse_nardin": {
        "reference_patterns": [r"\b(\d{3}-[A-Z0-9]{2,}(?:/[A-Z0-9]+)?)\b"],
        "detail_fetch": True,
    },
    "piaget": {
        "reference_patterns": [r"\b([A-Z]{1,3}\d[A-Z0-9]{3,})\b"],
        "detail_fetch": True,
    },
    "glashutte_original": {
        "reference_patterns": [
            r"\b(\d{3}-\d{2}-\d{2}-\d{2}-\d{2})\b",
            r"\b(\d{2}-\d{2}-\d{2}-\d{2}-\d{2})\b",
            r"\b(\d{1}-\d{2}-\d{2}-\d{2}-\d{2}-\d{2})\b",
        ],
        "detail_fetch": True,
        "strict_reference_patterns": True,
    },
    "girard_perregaux": {
        "detail_fetch": True,
    },
}

DEFAULT_LISTING_MULTIPLIER = 6


def _strip_accents(text: str) -> str:
    normalized = unicodedata.normalize("NFKD", text)
    return "".join(char for char in normalized if not unicodedata.combining(char))


def _collapse_spaces(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


def normalize_text(text: str) -> str:
    normalized = _strip_accents(text).lower()
    normalized = re.sub(r"[^a-z0-9]+", " ", normalized)
    return _collapse_spaces(normalized)


def get_brand_rules(brand_id: Optional[str]) -> Dict[str, object]:
    return BRAND_RULES.get(brand_id or "", {})


def get_reference_patterns(brand_id: Optional[str]) -> List[Pattern]:
    rules = get_brand_rules(brand_id)
    patterns = rules.get("reference_patterns", [])
    return [re.compile(pattern, re.IGNORECASE) for pattern in patterns]


def normalize_reference(reference: str, brand_id: Optional[str]) -> str:
    cleaned = reference.strip()
    cleaned = re.sub(r"^(ref\.?|reference(?:\s+number)?|ref#)\s*[:\-]?\s*", "", cleaned, flags=re.IGNORECASE)
    if "|" in cleaned:
        cleaned = cleaned.split("|")[0].strip()
    cleaned = re.sub(r"\s*\(.*\)\s*$", "", cleaned).strip()
    if brand_id == "richard_mille":
        cleaned = cleaned.replace(" ", "")
    return cleaned


def allow_name_reference(brand_id: Optional[str]) -> bool:
    return bool(get_brand_rules(brand_id).get("allow_name_reference"))


def strict_reference_patterns(brand_id: Optional[str]) -> bool:
    return bool(get_brand_rules(brand_id).get("strict_reference_patterns"))


def should_fetch_details(brand_id: Optional[str]) -> bool:
    return bool(get_brand_rules(brand_id).get("detail_fetch"))


def get_listing_multiplier(brand_id: Optional[str]) -> int:
    return int(get_brand_rules(brand_id).get("listing_multiplier", DEFAULT_LISTING_MULTIPLIER))


def build_brand_aliases(brand_name: Optional[str], brand_id: Optional[str]) -> List[str]:
    if not brand_name:
        return []

    base = _collapse_spaces(brand_name)
    variants = {
        base,
        base.replace(".", ""),
        base.replace("&", "and"),
        base.replace("&", "and").replace(".", ""),
    }

    drop_tokens = int(get_brand_rules(brand_id).get("drop_leading_tokens", 0))
    if drop_tokens > 0:
        for variant in list(variants):
            parts = variant.split()
            if len(parts) > drop_tokens:
                variants.add(" ".join(parts[drop_tokens:]))

    for variant in list(variants):
        variants.add(_strip_accents(variant))

    clean_variants = {v.strip() for v in variants if v and v.strip()}
    return sorted(clean_variants, key=len, reverse=True)


def _alias_pattern(alias: str) -> Optional[Pattern]:
    tokens = re.findall(r"\w+", alias, flags=re.UNICODE)
    if not tokens:
        return None
    separator = r"(?:\W+|\s*and\s+)*"
    pattern = r"^\s*" + separator.join(re.escape(token) for token in tokens) + r"\b"
    return re.compile(pattern, re.IGNORECASE)


def strip_brand_prefix(title: str, brand_name: Optional[str], brand_id: Optional[str]) -> str:
    if not title or not brand_name:
        return title

    cleaned = title.strip()
    aliases = build_brand_aliases(brand_name, brand_id)

    for alias in aliases:
        pattern = _alias_pattern(alias)
        if not pattern:
            continue
        match = pattern.match(cleaned)
        if match:
            remainder = cleaned[match.end():]
            remainder = re.sub(r"^[\s\-:|,/]+", "", remainder)
            return remainder.strip()

    for alias in aliases:
        alias_compact = re.sub(r"[^a-z0-9]+", "", _strip_accents(alias).lower())
        title_compact = re.sub(r"[^a-z0-9]+", "", _strip_accents(cleaned).lower())
        if alias_compact and title_compact.startswith(alias_compact):
            count = 0
            idx = 0
            while idx < len(cleaned) and count < len(alias_compact):
                if cleaned[idx].isalnum():
                    count += 1
                idx += 1
            remainder = cleaned[idx:]
            remainder = re.sub(r"^[\s\-:|,/]+", "", remainder)
            return remainder.strip()

    return cleaned


def clean_display_name(
    title: str,
    brand_name: Optional[str],
    brand_id: Optional[str],
    manufacturer: Optional[str] = None,
) -> str:
    if not title:
        return title

    cleaned = strip_brand_prefix(title, brand_name, brand_id)

    if manufacturer and cleaned == title:
        cleaned = strip_brand_prefix(cleaned, manufacturer, brand_id)

    return cleaned or title


def is_valid_reference(ref: str, brand_id: Optional[str] = None, brand_name: Optional[str] = None) -> bool:
    """Check if reference looks like a valid watch reference number."""
    if not ref:
        return False
    ref = ref.strip()
    if len(ref) < 3:
        return False
    invalid = [
        "no",
        "papers",
        "box",
        "new",
        "used",
        "vintage",
        "rare",
        "mint",
        "long",
        "chromalight",
        "champagne",
    ]
    if ref.lower() in invalid:
        return False
    if brand_name and normalize_text(ref) == normalize_text(brand_name):
        return False
    patterns = get_reference_patterns(brand_id)
    for pattern in patterns:
        if pattern.search(ref):
            return True
    if patterns and strict_reference_patterns(brand_id):
        return False
    if allow_name_reference(brand_id):
        return True
    if not re.search(r"\d{4,}", ref):
        return False
    return True
