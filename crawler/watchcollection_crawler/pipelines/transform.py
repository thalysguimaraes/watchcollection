#!/usr/bin/env python3
import argparse
import json
from datetime import datetime
from pathlib import Path
from sqlite3 import Connection
from typing import Optional

from watchcollection_crawler.config import get_brand_by_name
from watchcollection_crawler.core.paths import WATCHCHARTS_OUTPUT_DIR, API_DATA_DIR, MARKETDATA_DB_PATH
from watchcollection_crawler.utils.strings import slugify
from watchcollection_crawler.brand_rules import clean_display_name
from watchcollection_crawler.reference_matcher import generate_aliases
from watchcollection_crawler.marketdata.series import get_history_points, get_combined_source_label, get_latest_price
from watchcollection_crawler.marketdata.models import SnapshotSource


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


def transform_model(
    wc_model: dict,
    image_manifest: dict,
    brand_name: str,
    brand_slug: str,
    db_conn: Optional[Connection] = None,
    chrono24_model: Optional[dict] = None,
) -> dict:
    wc_id = str(wc_model.get("watchcharts_id", ""))

    market_price = None
    db_price = None
    if db_conn and wc_id:
        db_price = get_latest_price(
            db_conn,
            wc_id,
            prefer_sources=[SnapshotSource.CHRONO24, SnapshotSource.WATCHCHARTS_CSV],
        )

    if db_price:
        market_price = {
            "median_usd": db_price["median_usd"],
            "min_usd": db_price["min_usd"],
            "max_usd": db_price["max_usd"],
            "listings": db_price["listings"],
            "updated_at": db_price["updated_at"],
        }
    elif chrono24_model and chrono24_model.get("market_price_usd"):
        market_price = {
            "median_usd": chrono24_model["market_price_usd"],
            "min_usd": chrono24_model.get("market_price_min_usd"),
            "max_usd": chrono24_model.get("market_price_max_usd"),
            "listings": chrono24_model.get("market_price_listings"),
            "updated_at": chrono24_model.get("market_price_updated_at") or datetime.now().isoformat(),
        }
    elif wc_model.get("market_price_usd"):
        market_price = {
            "median_usd": wc_model["market_price_usd"],
            "min_usd": wc_model.get("market_price_min_usd"),
            "max_usd": wc_model.get("market_price_max_usd"),
            "listings": wc_model.get("market_price_listings"),
            "updated_at": wc_model.get("market_price_updated_at") or datetime.now().isoformat(),
        }

    image_url = image_manifest.get(wc_id) or wc_model.get("image_url")

    case = transform_case(wc_model)
    movement = transform_movement(wc_model)

    complications = wc_model.get("complications", [])
    if not isinstance(complications, list):
        complications = []

    features = wc_model.get("features", [])
    if not isinstance(features, list):
        features = []

    market_price_history = None
    if db_conn and wc_id:
        db_points = get_history_points(
            db_conn,
            wc_id,
            prefer_sources=[SnapshotSource.WATCHCHARTS_CSV, SnapshotSource.CHRONO24],
            downsample="weekly",
        )
        if db_points:
            source_label = get_combined_source_label(db_conn, wc_id)
            market_price_history = {
                "source": source_label,
                "points": db_points,
            }

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


def transform_brand(
    wc_data: dict,
    image_manifest: dict,
    db_conn: Optional[Connection] = None,
    chrono24_data: Optional[dict] = None,
) -> dict:
    brand_slug = wc_data.get("brand_slug") or slugify(wc_data.get("brand", ""))
    brand_name = wc_data.get("brand", brand_slug)
    meta = resolve_brand_meta(brand_slug, brand_name)

    chrono24_lookup: dict[str, dict] = {}
    if chrono24_data:
        for m in chrono24_data.get("models", []):
            wc_id = m.get("watchcharts_id")
            if wc_id:
                chrono24_lookup[str(wc_id)] = m

    return {
        "id": brand_slug,
        "name": brand_name,
        "country": meta["country"],
        "tier": meta["tier"],
        "models": [
            transform_model(
                m,
                image_manifest,
                brand_name,
                brand_slug,
                db_conn,
                chrono24_lookup.get(str(m.get("watchcharts_id", ""))),
            )
            for m in wc_data.get("models", [])
        ],
    }


def iter_brand_files(input_dir: Path, brand_slug: Optional[str]) -> list[Path]:
    """Return base WatchCharts JSON files only (never _chrono24.json).

    Field-level enrichment from chrono24 is handled separately via
    load_chrono24_enrichment().
    """
    if brand_slug:
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
    )

    files = []
    for json_file in input_dir.glob("*.json"):
        if json_file.name in skip_files:
            continue
        if json_file.name.endswith(skip_suffixes):
            continue
        files.append(json_file)

    return sorted(files)


def load_chrono24_enrichment(input_dir: Path, slug: str) -> Optional[dict]:
    """Load chrono24 enrichment file if it exists."""
    chrono_file = input_dir / f"{slug}_chrono24.json"
    if chrono_file.exists():
        with open(chrono_file) as f:
            return json.load(f)
    return None


def transform_all(
    input_dir: Path,
    output_file: Path,
    manifest_dir: Path,
    brand_slug: Optional[str],
    db_path: Optional[Path] = None,
) -> None:
    brands = []
    db_conn = None

    if db_path and db_path.exists():
        from watchcollection_crawler.marketdata.db import get_conn, init_schema
        db_conn = get_conn(db_path)
        init_schema(db_conn)
        print(f"Using marketdata DB: {db_path}")

    try:
        for json_file in iter_brand_files(input_dir, brand_slug):
            if not json_file.exists():
                continue
            print(f"Processing {json_file.name}...")
            with open(json_file) as f:
                wc_data = json.load(f)

            slug = wc_data.get("brand_slug") or json_file.stem

            chrono24_data = load_chrono24_enrichment(input_dir, slug)
            if chrono24_data:
                print(f"  Loaded chrono24 enrichment for {slug}")

            image_manifest = load_image_manifest(manifest_dir, slug)
            if image_manifest:
                print(f"  Loaded manifest for {slug}: {len(image_manifest)} images")

            brand = transform_brand(wc_data, image_manifest, db_conn, chrono24_data)
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
    finally:
        if db_conn:
            db_conn.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="Transform WatchCharts output into API bundle")
    parser.add_argument("--input-dir", type=str, help="Directory containing WatchCharts JSON files")
    parser.add_argument("--manifest-dir", type=str, help="Directory containing image manifests")
    parser.add_argument("--output", type=str, help="Output bundle path")
    parser.add_argument("--brand-slug", type=str, help="Process a single brand (slug)")
    parser.add_argument(
        "--marketdata-db",
        type=str,
        help=f"Path to marketdata SQLite DB (default: {MARKETDATA_DB_PATH})",
    )
    args = parser.parse_args()

    input_dir = Path(args.input_dir) if args.input_dir else WATCHCHARTS_OUTPUT_DIR
    manifest_dir = Path(args.manifest_dir) if args.manifest_dir else input_dir
    output_file = Path(args.output) if args.output else API_DATA_DIR / "catalog_bundle.json"
    db_path = Path(args.marketdata_db) if args.marketdata_db else MARKETDATA_DB_PATH

    transform_all(input_dir, output_file, manifest_dir, args.brand_slug, db_path)


if __name__ == "__main__":
    main()
