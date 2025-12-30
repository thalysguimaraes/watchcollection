#!/usr/bin/env python3
import argparse
import json
import os
import re
import statistics
import time
from datetime import datetime, timezone
from typing import Optional, List, Dict, Any

try:
    from dotenv import load_dotenv
except Exception:
    load_dotenv = None

from watchcollection_crawler.core.flaresolverr import FlareSolverrClient
from watchcollection_crawler.core.paths import WATCHCHARTS_OUTPUT_DIR
from watchcollection_crawler.sources import chrono24 as chrono24_source

PRICE_MIN = 500
PRICE_MAX = 5_000_000


def parse_price_value(price_str: Optional[str]) -> Optional[int]:
    if not price_str:
        return None
    cleaned = re.sub(r"[^\d]", "", str(price_str))
    if not cleaned:
        return None
    try:
        value = int(cleaned)
    except ValueError:
        return None
    if value < PRICE_MIN or value > PRICE_MAX:
        return None
    return value


def remove_outliers_iqr(prices: List[int], k: float = 1.5) -> List[int]:
    if len(prices) < 4:
        return prices
    sorted_prices = sorted(prices)
    n = len(sorted_prices)
    q1_idx = n // 4
    q3_idx = (3 * n) // 4
    q1 = sorted_prices[q1_idx]
    q3 = sorted_prices[q3_idx]
    iqr = q3 - q1
    lower_bound = q1 - (k * iqr)
    upper_bound = q3 + (k * iqr)
    return [p for p in prices if lower_bound <= p <= upper_bound]


def calculate_price_stats(prices: List[int]) -> Optional[Dict[str, int]]:
    if not prices:
        return None
    cleaned = remove_outliers_iqr(prices)
    if not cleaned:
        cleaned = prices
    return {
        "min": min(cleaned),
        "max": max(cleaned),
        "median": int(statistics.median(cleaned)),
        "count": len(cleaned),
    }


def fetch_listings(
    brand: str,
    reference: str,
    limit: int,
    use_flaresolverr: bool,
    currency: Optional[str],
    client: Optional[FlareSolverrClient],
) -> List[Dict[str, Any]]:
    listings: List[Dict[str, Any]] = []
    page = 1
    while len(listings) < limit:
        page_results = chrono24_source.search_by_reference(
            brand,
            reference,
            limit=limit,
            use_flaresolverr=use_flaresolverr,
            client=client,
            page=page,
            currency=currency,
        )
        if not page_results:
            break
        listings.extend(page_results)
        page += 1
        if len(page_results) == 0:
            break
        time.sleep(0.5)
    return listings[:limit]


def resolve_input_output(
    brand: Optional[str],
    input_path: Optional[str],
    output_path: Optional[str],
) -> tuple[str, str, str]:
    if input_path:
        input_file = input_path
        brand_slug = brand or os.path.basename(input_path).replace(".json", "").replace("_watchcharts", "")
    else:
        if not brand:
            raise ValueError("Provide --brand or --input")
        brand_slug = brand.lower().replace(" ", "_")
        input_file = str(WATCHCHARTS_OUTPUT_DIR / f"{brand_slug}.json")
    output_file = output_path or str(WATCHCHARTS_OUTPUT_DIR / f"{brand_slug}_chrono24.json")
    return input_file, output_file, brand_slug


def enrich_models(
    data: Dict[str, Any],
    brand_name: str,
    listings_per_model: int,
    min_listings: int,
    currency: Optional[str],
    use_flaresolverr: bool,
    overwrite: bool,
    limit: Optional[int],
    sleep_s: float,
) -> Dict[str, Any]:
    models = data.get("models", [])
    total = len(models)
    if limit and limit > 0:
        models = models[:limit]

    print(
        f"Chrono24 market price: brand={brand_name} models={len(models)} total={total} listings={listings_per_model}",
        flush=True,
    )

    updated = 0
    skipped = 0
    missing_prices = 0

    client = None
    if use_flaresolverr:
        client = FlareSolverrClient()
        client.create_session()

    try:
        for idx, model in enumerate(models, 1):
            ref = model.get("reference")
            name = model.get("full_name", "")
            if not ref:
                print(f"[{idx}/{len(models)}] missing reference -> skip", flush=True)
                skipped += 1
                continue

            if model.get("market_price_usd") and not overwrite:
                existing_source = (model.get("market_price_source") or "").lower()
                if existing_source == "chrono24":
                    print(f"[{idx}/{len(models)}] {ref} {name} - skip (has chrono24 market price)", flush=True)
                    skipped += 1
                    continue

            print(f"[{idx}/{len(models)}] {ref} {name}", flush=True)

            listings = fetch_listings(
                brand=brand_name,
                reference=ref,
                limit=listings_per_model,
                use_flaresolverr=use_flaresolverr,
                currency=currency,
                client=client,
            )

            prices = []
            for listing in listings:
                value = parse_price_value(listing.get("price"))
                if value is not None:
                    prices.append(value)

            if len(prices) < min_listings:
                missing_prices += 1
                print(f"  - only {len(prices)} prices (min {min_listings})", flush=True)
                if sleep_s:
                    time.sleep(sleep_s)
                continue

            stats = calculate_price_stats(prices)
            if not stats:
                missing_prices += 1
                print("  - no usable prices", flush=True)
                if sleep_s:
                    time.sleep(sleep_s)
                continue

            model["market_price_usd"] = stats["median"]
            model["market_price_min_usd"] = stats["min"]
            model["market_price_max_usd"] = stats["max"]
            model["market_price_listings"] = stats["count"]
            model["market_price_updated_at"] = datetime.now(timezone.utc).isoformat()
            model["market_price_source"] = "chrono24"
            model["chrono24_currency"] = currency
            model["chrono24_listings_count"] = len(listings)

            updated += 1
            print(
                f"  - median ${stats['median']:,} (min ${stats['min']:,}, max ${stats['max']:,}, n={stats['count']})",
                flush=True,
            )

            if sleep_s:
                time.sleep(sleep_s)
    finally:
        if client:
            client.destroy_session()

    data["chrono24_market_updated_at"] = datetime.now(timezone.utc).isoformat()
    data["chrono24_market_updated_count"] = updated
    data["chrono24_market_skipped_count"] = skipped
    data["chrono24_market_missing_prices"] = missing_prices
    return data


def main() -> None:
    parser = argparse.ArgumentParser(description="Enrich WatchCharts models with Chrono24 market prices")
    parser.add_argument("--brand", type=str, help="Brand slug (e.g., rolex)")
    parser.add_argument("--input", type=str, help="Input JSON file")
    parser.add_argument("--output", type=str, help="Output JSON file")
    parser.add_argument("--limit", type=int, help="Limit number of models to process")
    parser.add_argument("--listings", type=int, default=40, help="Listings to fetch per model")
    parser.add_argument("--min-listings", type=int, default=6, help="Minimum prices required to save market price")
    parser.add_argument("--currency", type=str, default="USD", help="Currency code for Chrono24 search")
    parser.add_argument("--overwrite", action="store_true", help="Overwrite existing market prices")
    parser.add_argument("--no-flaresolverr", action="store_true", help="Disable FlareSolverr")
    parser.add_argument("--sleep", type=float, default=0.5, help="Sleep between models (seconds)")
    parser.add_argument("--dry-run", action="store_true", help="Only show matches without saving")
    parser.add_argument("--env-file", type=str, help="Path to .env file")

    args = parser.parse_args()

    if load_dotenv:
        env_file = args.env_file or os.getenv("WATCHCHARTS_ENV_FILE")
        if env_file:
            load_dotenv(env_file, override=True)
        else:
            load_dotenv()

    input_file, output_file, brand_slug = resolve_input_output(args.brand, args.input, args.output)

    with open(input_file, "r") as f:
        data = json.load(f)

    brand_name = data.get("brand") or brand_slug

    if args.dry_run:
        print("DRY RUN: no files will be written", flush=True)

    enriched = enrich_models(
        data=data,
        brand_name=brand_name,
        listings_per_model=args.listings,
        min_listings=args.min_listings,
        currency=args.currency,
        use_flaresolverr=not args.no_flaresolverr,
        overwrite=args.overwrite,
        limit=args.limit,
        sleep_s=args.sleep,
    )

    if not args.dry_run:
        with open(output_file, "w") as f:
            json.dump(enriched, f, indent=2, default=str)
        print(f"Saved {output_file}", flush=True)


if __name__ == "__main__":
    main()
