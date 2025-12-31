#!/usr/bin/env python3
import argparse
import csv
import json
import os
from datetime import date
from pathlib import Path
from typing import Dict, List, Optional, Tuple

ROOT_DIR = Path(__file__).resolve().parents[2]
OUTPUT_DIR = Path(os.getenv("WATCHCOLLECTION_OUTPUT_DIR", str(ROOT_DIR / "output")))
API_DATA_DIR = Path(
    os.getenv("WATCHCOLLECTION_API_DATA_DIR", str(ROOT_DIR.parent / "api" / "data"))
)
MARKETDATA_DB_PATH = Path(
    os.getenv("MARKETDATA_DB_PATH", str(OUTPUT_DIR / "marketdata.sqlite"))
)
from watchcollection_crawler.marketdata import (
    IngestStats,
    MarketSnapshot,
    SnapshotSource,
    finish_ingest_run,
    get_db,
    insert_snapshot,
    start_ingest_run,
)
from watchcollection_crawler.marketdata.import_watchcharts_csv import (
    build_catalog_lookup,
    iter_csv_files,
    normalize_brand_name,
    parse_csv_row,
    parse_filename,
)

PIPELINE_NAME = "watchcharts_csv_import"


def import_csv_file(
    csv_path: Path,
    as_of_date: date,
    lookup: Dict[Tuple[str, str], Tuple[str, str]],
    conn,
    dry_run: bool = False,
    verbose: bool = False,
) -> IngestStats:
    stats = IngestStats()
    snapshots: List[MarketSnapshot] = []

    with open(csv_path, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)

        for row_num, row in enumerate(reader, 1):
            stats.rows_in += 1

            try:
                parsed = parse_csv_row(row)
            except ValueError as e:
                stats.warnings += 1
                if verbose:
                    print(f"  [row {row_num}] Parse error: {e}", flush=True)
                continue

            normalized_brand = normalize_brand_name(parsed.brand_name)
            key = (normalized_brand, parsed.reference)

            if key not in lookup:
                stats.warnings += 1
                if verbose:
                    print(
                        f"  [row {row_num}] Not in catalog: {parsed.brand_name} {parsed.reference}",
                        flush=True,
                    )
                continue

            watchcharts_id, brand_slug = lookup[key]

            snapshot = MarketSnapshot(
                watchcharts_id=watchcharts_id,
                brand_slug=brand_slug,
                reference=parsed.reference,
                as_of_date=as_of_date,
                source=SnapshotSource.WATCHCHARTS_CSV,
                currency="USD",
                median_usd=parsed.price_usd_cents,
                min_usd=None,
                max_usd=None,
                listings_count=None,
                raw_json=parsed.raw_line,
            )
            snapshots.append(snapshot)

    if dry_run:
        stats.rows_out = len(snapshots)
        return stats

    for snapshot in snapshots:
        if insert_snapshot(conn, snapshot):
            stats.rows_out += 1

    conn.commit()
    return stats


def import_all_csvs(
    csv_dir: Path,
    catalog_path: Path,
    db_path: Path,
    dry_run: bool = False,
    limit: Optional[int] = None,
    verbose: bool = False,
) -> IngestStats:
    print("WatchCharts CSV Import", flush=True)
    print("=" * 50, flush=True)
    print(f"CSV directory: {csv_dir}", flush=True)
    print(f"Catalog: {catalog_path}", flush=True)
    print(f"Database: {db_path}", flush=True)
    print(f"Dry run: {dry_run}", flush=True)
    print(flush=True)

    print("Loading catalog...", flush=True)
    lookup = build_catalog_lookup(catalog_path)
    print(f"Loaded {len(lookup)} models from catalog", flush=True)
    print(flush=True)

    csv_files = list(iter_csv_files(csv_dir))
    if limit:
        csv_files = csv_files[:limit]

    print(f"Processing {len(csv_files)} CSV files...", flush=True)
    print(flush=True)

    total_stats = IngestStats()

    with get_db(db_path) as conn:
        meta = {
            "csv_dir": str(csv_dir),
            "catalog_path": str(catalog_path),
            "dry_run": dry_run,
            "limit": limit,
            "file_count": len(csv_files),
        }
        run_id = start_ingest_run(conn, PIPELINE_NAME, json.dumps(meta))

        for idx, csv_file in enumerate(csv_files, 1):
            try:
                brand_from_filename, as_of_date = parse_filename(csv_file.name)
            except ValueError as e:
                print(f"[{idx}/{len(csv_files)}] ERROR: {csv_file.name} - {e}", flush=True)
                total_stats.errors += 1
                continue

            print(
                f"[{idx}/{len(csv_files)}] {csv_file.name} (date: {as_of_date})",
                flush=True,
            )

            file_stats = import_csv_file(
                csv_path=csv_file,
                as_of_date=as_of_date,
                lookup=lookup,
                conn=conn,
                dry_run=dry_run,
                verbose=verbose,
            )

            duplicates = file_stats.rows_in - file_stats.warnings - file_stats.rows_out
            print(
                f"  Parsed: {file_stats.rows_in} | Matched: {file_stats.rows_in - file_stats.warnings} | "
                f"Inserted: {file_stats.rows_out} | Duplicates: {max(0, duplicates)} | "
                f"Warnings: {file_stats.warnings}",
                flush=True,
            )

            total_stats.rows_in += file_stats.rows_in
            total_stats.rows_out += file_stats.rows_out
            total_stats.warnings += file_stats.warnings
            total_stats.errors += file_stats.errors

        ok = total_stats.errors == 0
        finish_ingest_run(conn, run_id, total_stats, ok=ok)

    print(flush=True)
    print("Summary", flush=True)
    print("-" * 50, flush=True)
    print(f"Files processed: {len(csv_files)}", flush=True)
    print(f"Total rows in: {total_stats.rows_in}", flush=True)
    print(f"Total rows out: {total_stats.rows_out}", flush=True)
    print(f"Warnings (unmatched): {total_stats.warnings}", flush=True)
    print(f"Errors: {total_stats.errors}", flush=True)
    print(f"Ingest run ID: {run_id}", flush=True)

    return total_stats


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Import WatchCharts CSV price history exports into marketdata DB"
    )
    parser.add_argument(
        "--csv-dir",
        type=str,
        required=True,
        help="Directory containing CSV files",
    )
    parser.add_argument(
        "--catalog",
        type=str,
        default=None,
        help=f"Catalog bundle JSON path (default: {API_DATA_DIR / 'catalog_bundle.json'})",
    )
    parser.add_argument(
        "--db",
        type=str,
        default=None,
        help=f"Database path (default: {MARKETDATA_DB_PATH})",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Parse and validate without inserting into DB",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=None,
        help="Process only first N CSV files",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Print per-row status",
    )

    args = parser.parse_args()

    csv_dir = Path(args.csv_dir)
    if not csv_dir.is_dir():
        print(f"Error: CSV directory not found: {csv_dir}")
        return

    catalog_path = Path(args.catalog) if args.catalog else API_DATA_DIR / "catalog_bundle.json"
    if not catalog_path.is_file():
        print(f"Error: Catalog file not found: {catalog_path}")
        return

    db_path = Path(args.db) if args.db else MARKETDATA_DB_PATH

    import_all_csvs(
        csv_dir=csv_dir,
        catalog_path=catalog_path,
        db_path=db_path,
        dry_run=args.dry_run,
        limit=args.limit,
        verbose=args.verbose,
    )


if __name__ == "__main__":
    main()
