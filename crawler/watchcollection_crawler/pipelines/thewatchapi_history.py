#!/usr/bin/env python3
import argparse
import json
import os
import re
from typing import Optional, Dict, Any, List, Set

try:
    from dotenv import load_dotenv
except Exception:
    load_dotenv = None

from watchcollection_crawler.core.paths import WATCHCHARTS_OUTPUT_DIR
from watchcollection_crawler.schemas_watchcharts import MarketPriceHistory, MarketPriceHistoryPoint
from watchcollection_crawler.sources.thewatchapi import TheWatchAPIClient, parse_price_date


def _normalize_ref(ref: Optional[str]) -> str:
    if not ref:
        return ""
    return re.sub(r"[^A-Za-z0-9]+", "", ref).upper()


def _build_ref_index(api_refs: List[str]) -> Dict[str, str]:
    index: Dict[str, str] = {}
    for ref in api_refs:
        norm = _normalize_ref(ref)
        if norm and norm not in index:
            index[norm] = ref
    return index


def _history_to_schema(points: List[Dict[str, Any]]) -> Optional[MarketPriceHistory]:
    if not points:
        return None

    converted: List[MarketPriceHistoryPoint] = []
    max_ts: Optional[int] = None

    for point in points:
        date_str = point.get("date") or point.get("price_date")
        if not date_str:
            continue
        ts = parse_price_date(date_str)
        if ts is None:
            continue

        price = point.get("price") or point.get("price_usd")
        if price is None:
            continue

        max_ts = ts if max_ts is None else max(max_ts, ts)
        converted.append(MarketPriceHistoryPoint(
            timestamp=ts,
            price=float(price),
            min_price=None,
            max_price=None,
        ))

    if not converted:
        return None

    return MarketPriceHistory(
        region_id=0,
        variation_id=0,
        key="thewatchapi",
        currency="USD",
        points=converted,
        max_time=max_ts,
        source="thewatchapi",
    )


def resolve_input_output(
    brand: Optional[str],
    input_path: Optional[str],
    output_path: Optional[str],
) -> tuple:
    if input_path:
        brand_slug = brand or os.path.basename(input_path).replace(".json", "").replace("_watchcharts", "")
        inp = input_path
    else:
        brand_slug = brand or "rolex"
        chrono_input = os.path.join(WATCHCHARTS_OUTPUT_DIR, f"{brand_slug}_chrono24.json")
        base_input = os.path.join(WATCHCHARTS_OUTPUT_DIR, f"{brand_slug}.json")
        inp = chrono_input if os.path.exists(chrono_input) else base_input
    if output_path:
        out = output_path
    else:
        out = os.path.join(WATCHCHARTS_OUTPUT_DIR, f"{brand_slug}_thewatchapi.json")
    return inp, out, brand_slug


def enrich_models(
    data: Dict[str, Any],
    brand_name: str,
    client: TheWatchAPIClient,
    limit: Optional[int] = None,
    overwrite: bool = False,
    dry_run: bool = False,
) -> Dict[str, Any]:
    models = data.get("models", [])
    total = len(models)
    if limit and limit > 0:
        models = models[:limit]

    print(f"TheWatchAPI history: brand={brand_name} models={len(models)} total={total}", flush=True)

    print(f"Fetching reference list for brand: {brand_name}", flush=True)
    api_refs = client.list_references(brand_name)
    print(f"Found {len(api_refs)} references in TheWatchAPI", flush=True)

    ref_index = _build_ref_index(api_refs)
    matched = 0
    enriched = 0
    errors = 0

    for i, model in enumerate(models, 1):
        ref = model.get("reference")
        name = model.get("full_name", "")
        norm_ref = _normalize_ref(ref)

        existing = model.get("market_price_history")
        if existing and not overwrite:
            print(f"[{i}/{len(models)}] {ref} {name} - skip (has history)", flush=True)
            continue

        api_ref = ref_index.get(norm_ref)
        if not api_ref:
            print(f"[{i}/{len(models)}] {ref} {name} - no match in TheWatchAPI", flush=True)
            continue

        matched += 1
        print(f"[{i}/{len(models)}] {ref} {name} - matched: {api_ref}", flush=True)

        if dry_run:
            continue

        try:
            history_data = client.get_price_history(api_ref)
            history = _history_to_schema(history_data)
            if history:
                model["market_price_history"] = history.model_dump()
                enriched += 1
                print(f"  - {len(history.points)} price points", flush=True)
            else:
                print(f"  - no price data", flush=True)
        except Exception as exc:
            errors += 1
            print(f"  - error: {exc}", flush=True)

    print(f"Summary: matched={matched} enriched={enriched} errors={errors}", flush=True)
    return data


def main() -> None:
    parser = argparse.ArgumentParser(description="Enrich WatchCharts data with TheWatchAPI price history")
    parser.add_argument("--brand", type=str, help="Brand slug (default: rolex)")
    parser.add_argument("--input", type=str, help="Input JSON file")
    parser.add_argument("--output", type=str, help="Output JSON file")
    parser.add_argument("--limit", type=int, help="Limit number of models to process")
    parser.add_argument("--overwrite", action="store_true", help="Overwrite existing price history")
    parser.add_argument("--dry-run", action="store_true", help="Only show matches without fetching prices")
    parser.add_argument("--env-file", type=str, help="Path to .env file")
    parser.add_argument("--api-token", type=str, help="TheWatchAPI token (or set THEWATCHAPI_API_KEY env)")

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

    api_token = args.api_token or os.getenv("THEWATCHAPI_API_KEY")
    if not api_token:
        raise SystemExit("TheWatchAPI token required. Set --api-token or THEWATCHAPI_API_KEY env var.")

    client = TheWatchAPIClient(api_token=api_token)

    try:
        enriched = enrich_models(
            data=data,
            brand_name=brand_name,
            client=client,
            limit=args.limit,
            overwrite=args.overwrite,
            dry_run=args.dry_run,
        )
    finally:
        client.close()

    if not args.dry_run:
        with open(output_file, "w") as f:
            json.dump(enriched, f, indent=2)
        print(f"Saved TheWatchAPI history to {output_file}")
    else:
        print("Dry run complete - no output written")


if __name__ == "__main__":
    main()
