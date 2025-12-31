#!/usr/bin/env python3
import argparse
import csv
import json
import os
import re
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from typing import Dict, Iterator, List, Optional, Tuple

ROOT_DIR = Path(__file__).resolve().parents[2]
OUTPUT_DIR = Path(os.getenv("WATCHCOLLECTION_OUTPUT_DIR", str(ROOT_DIR / "output")))
WATCHCHARTS_OUTPUT_DIR = Path(
    os.getenv("WATCHCHARTS_OUTPUT_DIR", str(ROOT_DIR / "output_watchcharts"))
)
MARKETDATA_DB_PATH = Path(
    os.getenv("MARKETDATA_DB_PATH", str(OUTPUT_DIR / "marketdata.sqlite"))
)

from watchcollection_crawler.marketdata import SnapshotSource, get_db


@dataclass
class WatchCoverage:
    watchcharts_id: str
    brand_slug: str
    reference: str
    full_name: str
    watchcharts_url: str
    snapshot_count: int
    earliest_date: Optional[str]
    latest_date: Optional[str]


def iter_catalog_files(catalog_dir: Path) -> Iterator[Path]:
    pattern = re.compile(r"^[a-z0-9_-]+\.json$")
    for path in sorted(catalog_dir.glob("*.json")):
        if pattern.match(path.name) and not any(
            suffix in path.name
            for suffix in ["_chrono24", "_failed", "_checkpoint", "_listings", "_image_manifest"]
        ):
            yield path


def load_catalog_models(catalog_path: Path) -> List[Dict]:
    with open(catalog_path, "r", encoding="utf-8") as f:
        data = json.load(f)
    brand_slug = data.get("brand_slug", "")
    models = []
    for model in data.get("models", []):
        models.append({
            "watchcharts_id": model.get("watchcharts_id", ""),
            "brand_slug": brand_slug,
            "reference": model.get("reference", ""),
            "full_name": model.get("full_name", ""),
            "watchcharts_url": model.get("watchcharts_url", ""),
        })
    return models


def get_snapshot_stats(
    conn, watchcharts_id: str, source: Optional[SnapshotSource] = None
) -> Tuple[int, Optional[str], Optional[str]]:
    query = """
        SELECT
            COUNT(*) as count,
            MIN(as_of_date) as earliest,
            MAX(as_of_date) as latest
        FROM market_snapshot
        WHERE watchcharts_id = ?
    """
    params: List = [watchcharts_id]
    if source:
        query += " AND source = ?"
        params.append(source.value)

    row = conn.execute(query, params).fetchone()
    if row:
        return row["count"], row["earliest"], row["latest"]
    return 0, None, None


def generate_backfill_queue(
    catalog_dir: Path,
    db_path: Path,
    output_path: Path,
    min_points: int = 1,
    after_date: Optional[date] = None,
    brand_filter: Optional[str] = None,
    verbose: bool = False,
) -> int:
    print("Marketdata Backfill Queue Generator", flush=True)
    print("=" * 50, flush=True)
    print(f"Catalog directory: {catalog_dir}", flush=True)
    print(f"Database: {db_path}", flush=True)
    print(f"Output: {output_path}", flush=True)
    print(f"Min points filter: {min_points}", flush=True)
    if after_date:
        print(f"After date filter: {after_date}", flush=True)
    if brand_filter:
        print(f"Brand filter: {brand_filter}", flush=True)
    print(flush=True)

    catalog_files = list(iter_catalog_files(catalog_dir))
    if brand_filter:
        catalog_files = [f for f in catalog_files if f.stem == brand_filter]

    if not catalog_files:
        print("No catalog files found.", flush=True)
        return 0

    print(f"Found {len(catalog_files)} catalog file(s)", flush=True)
    print(flush=True)

    all_models: List[Dict] = []
    for catalog_file in catalog_files:
        models = load_catalog_models(catalog_file)
        all_models.extend(models)
        if verbose:
            print(f"  {catalog_file.name}: {len(models)} models", flush=True)

    print(f"Total models in catalog: {len(all_models)}", flush=True)
    print(flush=True)

    queue: List[WatchCoverage] = []

    with get_db(db_path) as conn:
        print("Checking DB coverage...", flush=True)
        for model in all_models:
            watchcharts_id = model["watchcharts_id"]
            if not watchcharts_id:
                continue

            count, earliest, latest = get_snapshot_stats(
                conn, watchcharts_id, source=SnapshotSource.WATCHCHARTS_CSV
            )

            include = False
            if count < min_points:
                include = True
            elif after_date and earliest:
                earliest_dt = date.fromisoformat(earliest)
                if earliest_dt > after_date:
                    include = True

            if include:
                queue.append(WatchCoverage(
                    watchcharts_id=watchcharts_id,
                    brand_slug=model["brand_slug"],
                    reference=model["reference"],
                    full_name=model["full_name"],
                    watchcharts_url=model["watchcharts_url"],
                    snapshot_count=count,
                    earliest_date=earliest,
                    latest_date=latest,
                ))

    queue.sort(key=lambda x: (x.brand_slug, x.reference))

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w", newline="", encoding="utf-8") as f:
        fieldnames = [
            "watchcharts_id",
            "brand_slug",
            "reference",
            "full_name",
            "watchcharts_url",
            "snapshot_count",
            "earliest_date",
            "latest_date",
        ]
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for item in queue:
            writer.writerow({
                "watchcharts_id": item.watchcharts_id,
                "brand_slug": item.brand_slug,
                "reference": item.reference,
                "full_name": item.full_name,
                "watchcharts_url": item.watchcharts_url,
                "snapshot_count": item.snapshot_count,
                "earliest_date": item.earliest_date or "",
                "latest_date": item.latest_date or "",
            })

    print(flush=True)
    print("Summary", flush=True)
    print("-" * 50, flush=True)
    print(f"Models checked: {len(all_models)}", flush=True)
    print(f"Models needing backfill: {len(queue)}", flush=True)
    print(f"Output written to: {output_path}", flush=True)

    return len(queue)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate CSV queue of watches needing price history backfill"
    )
    parser.add_argument(
        "--output",
        type=str,
        default="backfill_queue.csv",
        help="Output CSV path (default: backfill_queue.csv)",
    )
    parser.add_argument(
        "--catalog-dir",
        type=str,
        default=None,
        help=f"WatchCharts catalog directory (default: {WATCHCHARTS_OUTPUT_DIR})",
    )
    parser.add_argument(
        "--db",
        type=str,
        default=None,
        help=f"Database path (default: {MARKETDATA_DB_PATH})",
    )
    parser.add_argument(
        "--min-points",
        type=int,
        default=1,
        help="Include watches with fewer than N snapshots (default: 1 = missing any)",
    )
    parser.add_argument(
        "--after-date",
        type=str,
        default=None,
        help="Include watches with history starting after YYYY-MM-DD",
    )
    parser.add_argument(
        "--brand",
        type=str,
        default=None,
        help="Filter to specific brand slug",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Print detailed progress",
    )

    args = parser.parse_args()

    catalog_dir = Path(args.catalog_dir) if args.catalog_dir else WATCHCHARTS_OUTPUT_DIR
    if not catalog_dir.is_dir():
        print(f"Error: Catalog directory not found: {catalog_dir}")
        return

    db_path = Path(args.db) if args.db else MARKETDATA_DB_PATH
    output_path = Path(args.output)

    after_date = None
    if args.after_date:
        try:
            after_date = date.fromisoformat(args.after_date)
        except ValueError:
            print(f"Error: Invalid date format: {args.after_date} (use YYYY-MM-DD)")
            return

    generate_backfill_queue(
        catalog_dir=catalog_dir,
        db_path=db_path,
        output_path=output_path,
        min_points=args.min_points,
        after_date=after_date,
        brand_filter=args.brand,
        verbose=args.verbose,
    )


if __name__ == "__main__":
    main()
