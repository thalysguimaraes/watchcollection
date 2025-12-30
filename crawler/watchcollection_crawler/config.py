import os
from typing import Optional, List
from dotenv import load_dotenv

load_dotenv()

FLARESOLVERR_URL = os.getenv("FLARESOLVERR_URL", "http://localhost:8191/v1")

BRANDS = {
    "holy_trinity": [
        {"id": "patek_philippe", "name": "Patek Philippe", "country": "Switzerland"},
        {"id": "audemars_piguet", "name": "Audemars Piguet", "country": "Switzerland"},
        {"id": "vacheron_constantin", "name": "Vacheron Constantin", "country": "Switzerland"},
    ],
    "ultra_luxury": [
        {"id": "richard_mille", "name": "Richard Mille", "country": "Switzerland"},
        {"id": "fp_journe", "name": "F.P. Journe", "country": "Switzerland"},
        {"id": "mb_and_f", "name": "MB&F", "country": "Switzerland"},
    ],
    "luxury": [
        {"id": "rolex", "name": "Rolex", "country": "Switzerland"},
        {"id": "a_lange_sohne", "name": "A. Lange & Söhne", "country": "Germany"},
        {"id": "jaeger_lecoultre", "name": "Jaeger-LeCoultre", "country": "Switzerland"},
        {"id": "blancpain", "name": "Blancpain", "country": "Switzerland"},
        {"id": "breguet", "name": "Breguet", "country": "Switzerland"},
        {"id": "hublot", "name": "Hublot", "country": "Switzerland"},
        {"id": "ulysse_nardin", "name": "Ulysse Nardin", "country": "Switzerland"},
        {"id": "chopard", "name": "Chopard", "country": "Switzerland"},
        {"id": "girard_perregaux", "name": "Girard-Perregaux", "country": "Switzerland"},
        {"id": "piaget", "name": "Piaget", "country": "Switzerland"},
        {"id": "glashutte_original", "name": "Glashütte Original", "country": "Germany"},
    ],
    "premium": [
        {"id": "omega", "name": "Omega", "country": "Switzerland"},
        {"id": "cartier", "name": "Cartier", "country": "France"},
        {"id": "iwc", "name": "IWC Schaffhausen", "country": "Switzerland"},
        {"id": "panerai", "name": "Panerai", "country": "Italy"},
        {"id": "breitling", "name": "Breitling", "country": "Switzerland"},
        {"id": "zenith", "name": "Zenith", "country": "Switzerland"},
        {"id": "bell_ross", "name": "Bell & Ross", "country": "France"},
        {"id": "baume_mercier", "name": "Baume & Mercier", "country": "Switzerland"},
    ],
    "upper_mid": [
        {"id": "tudor", "name": "Tudor", "country": "Switzerland"},
        {"id": "grand_seiko", "name": "Grand Seiko", "country": "Japan"},
        {"id": "tag_heuer", "name": "TAG Heuer", "country": "Switzerland"},
        {"id": "longines", "name": "Longines", "country": "Switzerland"},
        {"id": "oris", "name": "Oris", "country": "Switzerland"},
        {"id": "rado", "name": "Rado", "country": "Switzerland"},
        {"id": "frederique_constant", "name": "Frederique Constant", "country": "Switzerland"},
        {"id": "maurice_lacroix", "name": "Maurice Lacroix", "country": "Switzerland"},
    ],
    "independent": [
        {"id": "h_moser", "name": "H. Moser & Cie", "country": "Switzerland"},
        {"id": "nomos", "name": "Nomos Glashütte", "country": "Germany"},
        {"id": "sinn", "name": "Sinn", "country": "Germany"},
        {"id": "junghans", "name": "Junghans", "country": "Germany"},
        {"id": "montblanc", "name": "Montblanc", "country": "Germany"},
    ],
    "accessible": [
        {"id": "tissot", "name": "Tissot", "country": "Switzerland"},
        {"id": "hamilton", "name": "Hamilton", "country": "USA"},
        {"id": "seiko", "name": "Seiko", "country": "Japan"},
        {"id": "orient", "name": "Orient", "country": "Japan"},
        {"id": "casio_gshock", "name": "Casio G-Shock", "country": "Japan"},
        {"id": "citizen", "name": "Citizen", "country": "Japan"},
        {"id": "mido", "name": "Mido", "country": "Switzerland"},
        {"id": "certina", "name": "Certina", "country": "Switzerland"},
    ],
}

PHASES = {
    1: ["holy_trinity", "ultra_luxury", "luxury"],
    2: ["premium"],
    3: ["upper_mid", "independent", "accessible"],
}

def get_brands_for_phase(phase: int) -> list:
    tiers = PHASES.get(phase, [])
    brands = []
    for tier in tiers:
        for brand in BRANDS.get(tier, []):
            brands.append({**brand, "tier": tier})
    return brands

def get_all_brands() -> list:
    brands = []
    for tier, tier_brands in BRANDS.items():
        for brand in tier_brands:
            brands.append({**brand, "tier": tier})
    return brands

def get_brand_by_name(name: str) -> Optional[dict]:
    for tier, tier_brands in BRANDS.items():
        for brand in tier_brands:
            if brand["name"].lower() == name.lower() or brand["id"] == name.lower():
                return {**brand, "tier": tier}
    return None
