import re
import json
from pathlib import Path
from typing import Dict, List, Optional, Set

NORMALIZATION_RULES: Dict[str, Dict[str, bool]] = {
    "omega": {
        "strip_leading_zeros": True,
        "generate_zero_padded_aliases": True,
    },
    "tudor": {
        "strip_variant_suffix": True,
        "color_letter_as_alias": True,
    },
    "cartier": {
        "use_manual_mapping": True,
    },
    "iwc": {
        "strip_iw_prefix": True,
    },
    "grand_seiko": {
        "rebrand_offset": True,
    },
    "patek_philippe": {
        "strip_dial_suffix": True,
    },
    "rolex": {
        "strip_bezel_suffix": True,
    },
    "audemars_piguet": {
        "strip_material_suffix": True,
    },
    "panerai": {
        "normalize_pam_padding": True,
    },
    "breitling": {
        "extract_base_ref": True,
    },
}

TUDOR_COLOR_SUFFIXES = {"N", "B", "G", "R", "W", "S", "P"}

_cartier_aliases_cache: Optional[Dict[str, List[str]]] = None


def _load_cartier_aliases() -> Dict[str, List[str]]:
    global _cartier_aliases_cache
    if _cartier_aliases_cache is not None:
        return _cartier_aliases_cache

    aliases_path = Path(__file__).parent.parent / "data" / "cartier_aliases.json"
    if aliases_path.exists():
        with open(aliases_path, "r", encoding="utf-8") as f:
            _cartier_aliases_cache = json.load(f)
    else:
        _cartier_aliases_cache = {}
    return _cartier_aliases_cache


def _get_rules(brand_id: Optional[str]) -> Dict[str, bool]:
    return NORMALIZATION_RULES.get(brand_id or "", {})


def _strip_omega_zeros(ref: str) -> str:
    parts = ref.split(".")
    if len(parts) != 2:
        return ref
    left, right = parts
    right_stripped = right.lstrip("0") or "0"
    return f"{left}.{right_stripped}"


def _generate_omega_aliases(ref: str) -> List[str]:
    aliases: Set[str] = set()
    parts = ref.split(".")
    if len(parts) != 2:
        return []

    left, right = parts
    stripped = right.lstrip("0") or "0"

    for padding in range(1, 5):
        padded = right.zfill(padding)
        if padded != right:
            aliases.add(f"{left}.{padded}")

    if stripped != right:
        aliases.add(f"{left}.{stripped}")

    aliases.discard(ref)
    return sorted(aliases)


def _strip_tudor_suffix(ref: str) -> str:
    match = re.match(r"^(\d+)-\d+$", ref)
    if match:
        return match.group(1)
    return ref


def _strip_tudor_color_letter(ref: str) -> tuple[str, Optional[str]]:
    if len(ref) >= 2 and ref[-1].upper() in TUDOR_COLOR_SUFFIXES and ref[-2].isdigit():
        return ref[:-1], ref[-1].upper()
    return ref, None


def _generate_tudor_aliases(ref: str) -> List[str]:
    aliases: Set[str] = set()

    base_ref = _strip_tudor_suffix(ref)
    if base_ref != ref:
        aliases.add(base_ref)

    base_no_color, color = _strip_tudor_color_letter(base_ref)
    if color:
        aliases.add(base_no_color)
        for suffix in TUDOR_COLOR_SUFFIXES:
            variant = f"{base_no_color}{suffix}"
            if variant != ref:
                aliases.add(variant)

    for variant_num in ["0001", "0002", "0003", "0004"]:
        variant = f"{base_no_color}-{variant_num}"
        if variant != ref:
            aliases.add(variant)

    current_aliases = list(aliases)
    for alias in current_aliases:
        aliases.add(f"M{alias}")
    if not ref.startswith("M"):
        aliases.add(f"M{ref}")

    aliases.discard(ref)
    return sorted(aliases)


def _get_cartier_aliases(ref: str) -> List[str]:
    aliases_map = _load_cartier_aliases()
    return aliases_map.get(ref, [])


def _strip_iwc_prefix(ref: str) -> str:
    upper = ref.upper()
    if upper.startswith("IW"):
        return ref[2:]
    return ref


def _generate_iwc_aliases(ref: str) -> List[str]:
    aliases: Set[str] = set()
    upper = ref.upper()
    if upper.startswith("IW"):
        aliases.add(ref[2:])
    else:
        aliases.add(f"IW{ref}")
    aliases.discard(ref)
    return sorted(aliases)


def _normalize_grand_seiko_ref(ref: str) -> str:
    return ref.upper()


def _generate_grand_seiko_aliases(ref: str) -> List[str]:
    aliases: Set[str] = set()
    upper = ref.upper()
    match = re.match(r"^(SB[A-Z]{2})(\d{3})([A-Z]?)$", upper)
    if match:
        prefix, num_str, suffix = match.groups()
        num = int(num_str)
        if num < 200:
            aliases.add(f"{prefix}{num + 200:03d}{suffix}")
        elif 200 <= num < 400:
            aliases.add(f"{prefix}{num - 200:03d}{suffix}")
    aliases.discard(ref)
    aliases.discard(upper)
    return sorted(aliases)


def _strip_patek_suffix(ref: str) -> str:
    match = re.match(r"^(\d{4}/\d+[A-Z]*)", ref)
    if match:
        return match.group(1)
    match = re.match(r"^(\d{4}[A-Z]?)", ref)
    if match:
        return match.group(1)
    return ref


def _generate_patek_aliases(ref: str) -> List[str]:
    aliases: Set[str] = set()
    base = _strip_patek_suffix(ref)
    if base != ref:
        aliases.add(base)
    aliases.discard(ref)
    return sorted(aliases)


ROLEX_BEZEL_SUFFIXES = {
    "LN", "LV", "LB", "LC", "LG",
    "BLNR", "BLRO", "CHNR", "CLNR",
    "SARU", "SAUS",
    "BKSO", "DKMD",
}


def _strip_rolex_bezel(ref: str) -> str:
    upper = ref.upper()
    for suffix in sorted(ROLEX_BEZEL_SUFFIXES, key=len, reverse=True):
        if upper.endswith(suffix):
            return ref[:-len(suffix)]
    return ref


def _generate_rolex_aliases(ref: str) -> List[str]:
    aliases: Set[str] = set()
    base = _strip_rolex_bezel(ref)
    if base != ref:
        aliases.add(base)
        for suffix in ROLEX_BEZEL_SUFFIXES:
            variant = f"{base}{suffix}"
            if variant.upper() != ref.upper():
                aliases.add(variant)
    aliases.discard(ref)
    return sorted(aliases)


AP_MATERIAL_SUFFIXES = {
    "ST", "OR", "BA", "BC", "CE", "TI",
    "OO", "IO", "SO", "RO", "NO", "PO", "CO", "TO", "BO", "DO", "GO", "HO", "KO", "MO",
}


def _strip_ap_material(ref: str) -> str:
    upper = ref.upper()
    for suffix in sorted(AP_MATERIAL_SUFFIXES, key=len, reverse=True):
        if upper.endswith(suffix) and len(ref) > len(suffix):
            base = ref[:-len(suffix)]
            if base and base[-1].isdigit():
                return base
    return ref


def _generate_ap_aliases(ref: str) -> List[str]:
    aliases: Set[str] = set()
    base = _strip_ap_material(ref)
    if base != ref:
        aliases.add(base)
        for suffix in ["ST", "OR", "BA", "BC", "CE", "TI"]:
            variant = f"{base}{suffix}"
            if variant.upper() != ref.upper():
                aliases.add(variant)
    aliases.discard(ref)
    return sorted(aliases)


def _normalize_panerai_ref(ref: str) -> str:
    upper = ref.upper()
    match = re.match(r"^PAM0*(\d+)$", upper)
    if match:
        num = match.group(1)
        return f"PAM{int(num):05d}"
    return ref


def _generate_panerai_aliases(ref: str) -> List[str]:
    aliases: Set[str] = set()
    upper = ref.upper()
    match = re.match(r"^PAM0*(\d+)$", upper)
    if match:
        num = int(match.group(1))
        aliases.add(f"PAM{num}")
        aliases.add(f"PAM{num:03d}")
        aliases.add(f"PAM{num:05d}")
        aliases.add(f"PAM00{num}")
    aliases.discard(ref)
    aliases.discard(upper)
    return sorted(aliases)


def _strip_breitling_base(ref: str) -> str:
    upper = ref.upper()
    match = re.match(r"^([A-Z]{1,2}\d{4})", upper)
    if match:
        return match.group(1)
    return ref


def _generate_breitling_aliases(ref: str) -> List[str]:
    aliases: Set[str] = set()
    base = _strip_breitling_base(ref)
    if base != ref:
        aliases.add(base)
    aliases.discard(ref)
    return sorted(aliases)


def normalize_for_matching(ref: str, brand_id: Optional[str] = None) -> str:
    if not ref:
        return ref

    ref = ref.strip()
    rules = _get_rules(brand_id)

    if rules.get("strip_leading_zeros") and brand_id == "omega":
        ref = _strip_omega_zeros(ref)

    if rules.get("strip_variant_suffix") and brand_id == "tudor":
        ref = _strip_tudor_suffix(ref)
        ref, _ = _strip_tudor_color_letter(ref)

    if rules.get("strip_iw_prefix") and brand_id == "iwc":
        ref = _strip_iwc_prefix(ref)

    if rules.get("strip_dial_suffix") and brand_id == "patek_philippe":
        ref = _strip_patek_suffix(ref)

    if rules.get("strip_bezel_suffix") and brand_id == "rolex":
        ref = _strip_rolex_bezel(ref)

    if rules.get("strip_material_suffix") and brand_id == "audemars_piguet":
        ref = _strip_ap_material(ref)

    if rules.get("normalize_pam_padding") and brand_id == "panerai":
        ref = _normalize_panerai_ref(ref)

    if rules.get("extract_base_ref") and brand_id == "breitling":
        ref = _strip_breitling_base(ref)

    return ref


def generate_aliases(canonical_ref: str, brand_id: Optional[str] = None) -> List[str]:
    if not canonical_ref:
        return []

    aliases: Set[str] = set()
    rules = _get_rules(brand_id)

    if rules.get("generate_zero_padded_aliases") and brand_id == "omega":
        aliases.update(_generate_omega_aliases(canonical_ref))

    if brand_id == "tudor":
        aliases.update(_generate_tudor_aliases(canonical_ref))

    if rules.get("use_manual_mapping") and brand_id == "cartier":
        aliases.update(_get_cartier_aliases(canonical_ref))

    if rules.get("strip_iw_prefix") and brand_id == "iwc":
        aliases.update(_generate_iwc_aliases(canonical_ref))

    if rules.get("rebrand_offset") and brand_id == "grand_seiko":
        aliases.update(_generate_grand_seiko_aliases(canonical_ref))

    if rules.get("strip_dial_suffix") and brand_id == "patek_philippe":
        aliases.update(_generate_patek_aliases(canonical_ref))

    if rules.get("strip_bezel_suffix") and brand_id == "rolex":
        aliases.update(_generate_rolex_aliases(canonical_ref))

    if rules.get("strip_material_suffix") and brand_id == "audemars_piguet":
        aliases.update(_generate_ap_aliases(canonical_ref))

    if rules.get("normalize_pam_padding") and brand_id == "panerai":
        aliases.update(_generate_panerai_aliases(canonical_ref))

    if rules.get("extract_base_ref") and brand_id == "breitling":
        aliases.update(_generate_breitling_aliases(canonical_ref))

    return sorted(aliases)


def refs_match(ref1: str, ref2: str, brand_id: Optional[str] = None) -> bool:
    if not ref1 or not ref2:
        return False

    if ref1 == ref2:
        return True

    norm1 = normalize_for_matching(ref1, brand_id)
    norm2 = normalize_for_matching(ref2, brand_id)

    if norm1 == norm2:
        return True

    aliases1 = set(generate_aliases(ref1, brand_id))
    aliases1.add(ref1)
    aliases1.add(norm1)

    aliases2 = set(generate_aliases(ref2, brand_id))
    aliases2.add(ref2)
    aliases2.add(norm2)

    return bool(aliases1 & aliases2)
