#!/usr/bin/env python3
import argparse
import json
from datetime import datetime
from pathlib import Path
from typing import Optional

from watchcollection_crawler.config import get_brand_by_name
from watchcollection_crawler.core.paths import WATCHCHARTS_OUTPUT_DIR, API_DATA_DIR
from watchcollection_crawler.utils.strings import slugify
from watchcollection_crawler.brand_rules import clean_display_name
from watchcollection_crawler.reference_matcher import generate_aliases


def load_image_manifest(manifest_dir: Path, brand_slug: str) -> dict:
    candidates = [
        manifest_dir / f"{brand_slug}_image_manifest.json",
        manifest_dir / "image_manifest.json",
    ]
    for path in candidates:
        if path.exists():
            with open(path) as f:
                return json.load(f)
    return {}


def resolve_brand_meta(brand_slug: str, brand_name: str) -> dict:
    meta = get_brand_by_name(brand_name) or get_brand_by_name(brand_slug)
    if meta:
        return {"country": meta.get("country"), "tier": meta.get("tier")}
    return {"country": None, "tier": None}


def transform_case(wc_model: dict) -> Optional[dict]:
    case_data = wc_model.get("case")
    if case_data and isinstance(case_data, dict):
        return {
            "diameter_mm": case_data.get("diameter_mm"),
            "thickness_mm": case_data.get("thickness_mm"),
            "material": case_data.get("material"),
            "bezel_material": case_data.get("bezel_material"),
            "crystal": case_data.get("crystal"),
            "water_resistance_m": case_data.get("water_resistance_m"),
            "lug_width_mm": case_data.get("lug_width_mm"),
            "dial_color": case_data.get("dial_color"),
            "dial_numerals": case_data.get("dial_numerals"),
        }

    if wc_model.get("case_diameter_mm") or wc_model.get("case_material"):
        return {
            "diameter_mm": wc_model.get("case_diameter_mm"),
            "thickness_mm": wc_model.get("case_thickness_mm"),
            "material": wc_model.get("case_material"),
            "bezel_material": wc_model.get("bezel_material"),
            "crystal": wc_model.get("crystal"),
            "water_resistance_m": wc_model.get("water_resistance_m"),
            "lug_width_mm": None,
            "dial_color": wc_model.get("dial_color"),
            "dial_numerals": None,
        }

    return None


def transform_movement(wc_model: dict) -> Optional[dict]:
    movement_data = wc_model.get("movement")
    if movement_data and isinstance(movement_data, dict):
        return {
            "type": movement_data.get("type"),
            "caliber": movement_data.get("caliber"),
            "power_reserve_hours": movement_data.get("power_reserve_hours"),
            "frequency_bph": movement_data.get("frequency_bph"),
            "jewels_count": movement_data.get("jewels_count"),
        }

    if wc_model.get("movement_type") or wc_model.get("caliber"):
        return {
            "type": wc_model.get("movement_type"),
            "caliber": wc_model.get("caliber"),
            "power_reserve_hours": wc_model.get("power_reserve_hours"),
            "frequency_bph": None,
            "jewels_count": None,
        }

    return None


def transform_price_history(history_data: Optional[dict]) -> Optional[dict]:
    if not history_data:
        return None
    points = history_data.get("points", [])
    if not points:
        return None
    compressed = []
    for pt in points:
        ts = pt.get("timestamp")
        price = pt.get("price")
        if ts is not None and price is not None:
            compressed.append([ts, round(price, 2)])
    if not compressed:
        return None
    return {
        "source": history_data.get("source", "unknown"),
        "points": compressed,
    }


def transform_model(wc_model: dict, image_manifest: dict, brand_name: str, brand_slug: str) -> dict:
    market_price = None
    if wc_model.get("market_price_usd"):
        market_price = {
            "median_usd": wc_model["market_price_usd"],
            "min_usd": wc_model.get("market_price_min_usd"),
            "max_usd": wc_model.get("market_price_max_usd"),
            "listings": wc_model.get("market_price_listings"),
            "updated_at": wc_model.get("market_price_updated_at") or datetime.now().isoformat(),
        }

    wc_id = str(wc_model.get("watchcharts_id", ""))
    image_url = image_manifest.get(wc_id) or wc_model.get("image_url")

    case = transform_case(wc_model)
    movement = transform_movement(wc_model)

    complications = wc_model.get("complications", [])
    if not isinstance(complications, list):
        complications = []

    features = wc_model.get("features", [])
    if not isinstance(features, list):
        features = []

    market_price_history = transform_price_history(wc_model.get("market_price_history"))

    display_name = clean_display_name(wc_model["full_name"], brand_name, brand_slug)

    existing_aliases = wc_model.get("reference_aliases", [])
    if not isinstance(existing_aliases, list):
        existing_aliases = []

    generated_aliases = generate_aliases(wc_model["reference"], brand_slug)
    all_aliases = list(set(existing_aliases + generated_aliases))

    return {
        "reference": wc_model["reference"],
        "reference_aliases": sorted(all_aliases),
        "display_name": display_name,
        "collection": wc_model.get("collection"),
        "style": wc_model.get("style"),
        "case": case,
        "movement": movement,
        "complications": complications,
        "features": features,
        "retail_price_usd": wc_model.get("retail_price_usd"),
        "catalog_image_url": image_url,
        "market_price": market_price,
        "market_price_history": market_price_history,
        "watchcharts_id": wc_model.get("watchcharts_id"),
        "watchcharts_url": wc_model.get("watchcharts_url"),
        "is_current": wc_model.get("is_current"),
    }


def transform_brand(wc_data: dict, image_manifest: dict) -> dict:
    brand_slug = wc_data.get("brand_slug") or slugify(wc_data.get("brand", ""))
    brand_name = wc_data.get("brand", brand_slug)
    meta = resolve_brand_meta(brand_slug, brand_name)

    return {
        "id": brand_slug,
        "name": brand_name,
        "country": meta["country"],
        "tier": meta["tier"],
        "models": [transform_model(m, image_manifest, brand_name, brand_slug) for m in wc_data.get("models", [])],
    }


def iter_brand_files(input_dir: Path, brand_slug: Optional[str]) -> list[Path]:
    if brand_slug:
        chrono = input_dir / f"{brand_slug}_chrono24.json"
        if chrono.exists():
            return [chrono]
        return [input_dir / f"{brand_slug}.json"]

    skip_files = {
        "catalog_bundle.json",
        "download_progress.json",
        "failed_downloads.json",
        "image_manifest.json",
    }
    skip_suffixes = (
        "_image_manifest.json",
        "_download_progress.json",
        "_failed_downloads.json",
        "_checkpoint.json",
        "_listings.json",
        "_failed.json",
        "_chrono24.json",
        "_thewatchapi.json",
    )

    files = []
    for json_file in input_dir.glob("*.json"):
        if json_file.name in skip_files:
            continue
        if json_file.name.endswith(skip_suffixes):
            continue
        slug = json_file.stem
        chrono = input_dir / f"{slug}_chrono24.json"
        if chrono.exists():
            files.append(chrono)
        else:
            files.append(json_file)

    return sorted(files)


def transform_all(input_dir: Path, output_file: Path, manifest_dir: Path, brand_slug: Optional[str]) -> None:
    brands = []

    for json_file in iter_brand_files(input_dir, brand_slug):
        if not json_file.exists():
            continue
        print(f"Processing {json_file.name}...")
        with open(json_file) as f:
            wc_data = json.load(f)

        slug = wc_data.get("brand_slug") or json_file.stem
        image_manifest = load_image_manifest(manifest_dir, slug)
        if image_manifest:
            print(f"  Loaded manifest for {slug}: {len(image_manifest)} images")

        brand = transform_brand(wc_data, image_manifest)
        brands.append(brand)
        print(f"  -> {brand['name']}: {len(brand['models'])} models")

    catalog = {
        "version": "4.0.0",
        "generated_at": datetime.now().isoformat(),
        "brands": brands,
    }

    output_file.parent.mkdir(parents=True, exist_ok=True)
    with open(output_file, "w") as f:
        json.dump(catalog, f, indent=2)

    total_models = sum(len(b["models"]) for b in brands)
    print(f"\nDone! Saved {len(brands)} brands, {total_models} models to {output_file}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Transform WatchCharts output into API bundle")
    parser.add_argument("--input-dir", type=str, help="Directory containing WatchCharts JSON files")
    parser.add_argument("--manifest-dir", type=str, help="Directory containing image manifests")
    parser.add_argument("--output", type=str, help="Output bundle path")
    parser.add_argument("--brand-slug", type=str, help="Process a single brand (slug)")
    args = parser.parse_args()

    input_dir = Path(args.input_dir) if args.input_dir else WATCHCHARTS_OUTPUT_DIR
    manifest_dir = Path(args.manifest_dir) if args.manifest_dir else input_dir
    output_file = Path(args.output) if args.output else API_DATA_DIR / "catalog_bundle.json"

    transform_all(input_dir, output_file, manifest_dir, args.brand_slug)


if __name__ == "__main__":
    main()
