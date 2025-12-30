#!/usr/bin/env python3
import argparse
import asyncio
import json
import os
import sys
import time
from dataclasses import dataclass
from io import BytesIO
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import httpx
from PIL import Image

try:
    from dotenv import load_dotenv
except Exception:
    load_dotenv = None

try:
    import boto3
    from botocore.config import Config as BotoConfig
except Exception:
    boto3 = None
    BotoConfig = None

try:
    import h2  # noqa: F401
except Exception:
    h2 = None

from watchcollection_crawler.core.flaresolverr import FlareSolverrClient
from watchcollection_crawler.core.paths import WATCHCHARTS_OUTPUT_DIR, WATCHCHARTS_IMAGES_DIR
from watchcollection_crawler.utils.strings import slugify

sys.stdout.reconfigure(line_buffering=True)
sys.stderr.reconfigure(line_buffering=True)

OUTPUT_DIR = WATCHCHARTS_OUTPUT_DIR
IMAGES_DIR = WATCHCHARTS_IMAGES_DIR

DEFAULT_HEADERS = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
    "Accept": "image/avif,image/webp,*/*",
    "Referer": "https://watchcharts.com/",
}

R2_PUBLIC_URL = os.getenv("R2_PUBLIC_URL", "").rstrip("/")
USE_FLARESOLVERR = os.getenv("USE_FLARESOLVERR", "true").lower() == "true"

MAX_WIDTH_DEFAULT = 800
WEBP_QUALITY_DEFAULT = 85
CHECKPOINT_EVERY_DEFAULT = 50
CHECKPOINT_INTERVAL_DEFAULT = 15.0


@dataclass
class PipelineConfig:
    output_dir: Path
    images_dir: Path
    r2_prefix: str
    max_width: int
    webp_quality: int
    download_timeout: float
    download_retries: int
    concurrency: int
    upload_concurrency: int
    checkpoint_every: int
    checkpoint_interval: float
    reuse_local: bool
    detail_fallback: bool
    use_flaresolverr: bool
    upload_enabled: bool
    r2_bucket: Optional[str]
    r2_public_url: str


def get_run_paths(output_dir: Path, brand_slug: str) -> Tuple[Path, Path, Path]:
    return (
        output_dir / f"{brand_slug}_image_manifest.json",
        output_dir / f"{brand_slug}_download_progress.json",
        output_dir / f"{brand_slug}_failed_downloads.json",
    )


def extract_image_url(html: str) -> Optional[str]:
    import re

    removebg_pattern = r"https://cdn\.watchcharts\.com/removebg/[a-f0-9-]+\.png"
    matches = re.findall(removebg_pattern, html)

    if matches:
        return matches[0]

    return None


def process_image(image_data: bytes, max_width: int, webp_quality: int) -> bytes:
    img = Image.open(BytesIO(image_data))

    if img.mode in ("RGBA", "P"):
        img = img.convert("RGB")

    if img.width > max_width:
        ratio = max_width / img.width
        new_height = int(img.height * ratio)
        img = img.resize((max_width, new_height), Image.Resampling.LANCZOS)

    output = BytesIO()
    img.save(output, format="WEBP", quality=webp_quality, optimize=True)
    return output.getvalue()


def load_progress(progress_file: Path) -> dict:
    if progress_file.exists():
        with open(progress_file) as f:
            return json.load(f)
    return {"completed": [], "manifest": {}}


def save_progress(progress_file: Path, completed: List[str], manifest: Dict[str, str]) -> None:
    with open(progress_file, "w") as f:
        json.dump({"completed": completed, "manifest": manifest}, f, indent=2)


def save_manifest(manifest_file: Path, manifest: Dict[str, str]) -> None:
    with open(manifest_file, "w") as f:
        json.dump(manifest, f, indent=2)


def save_failed(failed_file: Path, failed: List[dict]) -> None:
    with open(failed_file, "w") as f:
        json.dump(failed, f, indent=2)


def build_r2_client(endpoint_url: str, access_key: str, secret_key: str, max_connections: int) -> Any:
    if not boto3 or not BotoConfig:
        raise RuntimeError("boto3 is required for R2 uploads. Install with pip install boto3")

    config = BotoConfig(
        max_pool_connections=max_connections,
        retries={"max_attempts": 4},
    )
    return boto3.client(
        "s3",
        endpoint_url=endpoint_url,
        aws_access_key_id=access_key,
        aws_secret_access_key=secret_key,
        region_name="auto",
        config=config,
    )


class ProgressTracker:
    def __init__(
        self,
        progress_file: Path,
        checkpoint_every: int,
        checkpoint_interval: float,
        completed: List[str],
        manifest: Dict[str, str],
    ) -> None:
        self.progress_file = progress_file
        self.checkpoint_every = max(1, checkpoint_every)
        self.checkpoint_interval = max(1.0, checkpoint_interval)
        self.completed = set(completed)
        self.manifest = dict(manifest)
        self.failed: List[dict] = []
        self._lock = asyncio.Lock()
        self._since_save = 0
        self._last_save = time.monotonic()

    async def mark_success(self, wc_id: str, manifest_value: str) -> None:
        async with self._lock:
            self.completed.add(wc_id)
            self.manifest[wc_id] = manifest_value
            self._since_save += 1

    async def mark_failure(self, failure: dict) -> None:
        async with self._lock:
            self.failed.append(failure)
            self._since_save += 1

    async def maybe_save(self, force: bool = False) -> None:
        snapshot = None
        async with self._lock:
            now = time.monotonic()
            if not force:
                if self._since_save < self.checkpoint_every and (now - self._last_save) < self.checkpoint_interval:
                    return
            snapshot = (
                list(self.completed),
                dict(self.manifest),
            )
            self._since_save = 0
            self._last_save = now

        if snapshot:
            completed, manifest = snapshot
            await asyncio.to_thread(save_progress, self.progress_file, completed, manifest)

    async def finalize(self, manifest_file: Path, failed_file: Path) -> None:
        await self.maybe_save(force=True)
        await asyncio.to_thread(save_manifest, manifest_file, self.manifest)
        await asyncio.to_thread(save_failed, failed_file, self.failed)


async def fetch_detail_image_url(
    detail_url: str,
    client: httpx.AsyncClient,
    flare_client: Optional[FlareSolverrClient],
    use_flaresolverr: bool,
    timeout: float,
) -> Optional[str]:
    try:
        if use_flaresolverr and flare_client:
            html = await asyncio.to_thread(flare_client.get, detail_url, int(timeout * 1000))
        else:
            resp = await client.get(detail_url, timeout=timeout)
            html = resp.text
    except Exception:
        return None

    return extract_image_url(html)


async def download_bytes(
    url: str,
    client: httpx.AsyncClient,
    timeout: float,
    retries: int,
) -> bytes:
    last_error: Optional[Exception] = None
    for attempt in range(retries + 1):
        try:
            resp = await client.get(url, timeout=timeout)
            if resp.status_code == 200 and len(resp.content) > 1000:
                return resp.content
            last_error = RuntimeError(f"HTTP {resp.status_code}")
            if resp.status_code in {403, 404}:
                break
        except Exception as exc:
            last_error = exc
        if attempt < retries:
            await asyncio.sleep(0.5 * (2**attempt))
    raise RuntimeError(f"download_failed: {last_error}")


async def upload_to_r2(
    r2_client: Any,
    bucket: str,
    key: str,
    payload: bytes,
) -> None:
    await asyncio.to_thread(
        r2_client.put_object,
        Bucket=bucket,
        Key=key,
        Body=payload,
        ContentType="image/webp",
        CacheControl="public, max-age=31536000, immutable",
    )


async def handle_model(
    model: dict,
    client: httpx.AsyncClient,
    flare_client: Optional[FlareSolverrClient],
    tracker: ProgressTracker,
    config: PipelineConfig,
    r2_client: Optional[Any],
    upload_sem: asyncio.Semaphore,
) -> None:
    wc_id = str(model.get("watchcharts_id", "")).strip()
    if not wc_id:
        await tracker.mark_failure({"id": wc_id, "reason": "missing_watchcharts_id"})
        return

    if wc_id in tracker.completed:
        return

    local_path = config.images_dir / f"{wc_id}.webp"

    if config.reuse_local and local_path.exists():
        try:
            payload = await asyncio.to_thread(local_path.read_bytes)
        except Exception as exc:
            await tracker.mark_failure({"id": wc_id, "reason": f"read_local_failed: {exc}"})
            return
    else:
        image_url = model.get("image_url") or ""
        if not image_url and config.detail_fallback:
            detail_url = model.get("watchcharts_url")
            if detail_url:
                image_url = await fetch_detail_image_url(
                    detail_url=detail_url,
                    client=client,
                    flare_client=flare_client,
                    use_flaresolverr=config.use_flaresolverr,
                    timeout=config.download_timeout,
                ) or ""

        if not image_url:
            await tracker.mark_failure({"id": wc_id, "reason": "no_image_url"})
            return

        try:
            image_data = await download_bytes(
                image_url,
                client=client,
                timeout=config.download_timeout,
                retries=config.download_retries,
            )
        except Exception as exc:
            await tracker.mark_failure({"id": wc_id, "reason": str(exc)})
            return

        try:
            payload = await asyncio.to_thread(
                process_image,
                image_data,
                config.max_width,
                config.webp_quality,
            )
        except Exception as exc:
            await tracker.mark_failure({"id": wc_id, "reason": f"process_error: {exc}"})
            return

        try:
            await asyncio.to_thread(local_path.write_bytes, payload)
        except Exception as exc:
            await tracker.mark_failure({"id": wc_id, "reason": f"save_error: {exc}"})
            return

    key = f"{config.r2_prefix}/{wc_id}.webp"
    manifest_value = f"{config.r2_public_url}/{key}" if config.r2_public_url else key

    if config.upload_enabled:
        if not r2_client or not config.r2_bucket:
            await tracker.mark_failure({"id": wc_id, "reason": "r2_not_configured"})
            return
        async with upload_sem:
            try:
                await upload_to_r2(r2_client, config.r2_bucket, key, payload)
            except Exception as exc:
                await tracker.mark_failure({"id": wc_id, "reason": f"upload_failed: {exc}"})
                return

    await tracker.mark_success(wc_id, manifest_value)
    await tracker.maybe_save()


async def worker(
    name: str,
    queue: asyncio.Queue,
    client: httpx.AsyncClient,
    flare_client: Optional[FlareSolverrClient],
    tracker: ProgressTracker,
    config: PipelineConfig,
    r2_client: Optional[Any],
    upload_sem: asyncio.Semaphore,
) -> None:
    while True:
        model = await queue.get()
        try:
            if model is None:
                return
            await handle_model(model, client, flare_client, tracker, config, r2_client, upload_sem)
        finally:
            queue.task_done()


async def run_async(args: argparse.Namespace) -> None:
    if load_dotenv:
        env_file = args.env_file or os.getenv("R2_ENV_FILE")
        if env_file:
            load_dotenv(env_file, override=True)
        else:
            load_dotenv()

    brand_slug = args.brand_slug or (slugify(args.brand) if args.brand else None)
    if not brand_slug and args.input:
        brand_slug = Path(args.input).stem
    if not brand_slug and not args.input:
        raise SystemExit("Provide --brand/--brand-slug or --input")

    output_dir = Path(args.output_dir) if args.output_dir else OUTPUT_DIR
    images_dir = Path(args.images_dir) if args.images_dir else IMAGES_DIR
    output_dir.mkdir(exist_ok=True)
    images_dir.mkdir(exist_ok=True)

    catalog_file = Path(args.input) if args.input else output_dir / f"{brand_slug}.json"
    if not catalog_file.exists():
        raise SystemExit(f"Error: {catalog_file} not found")

    data = json.loads(catalog_file.read_text())
    models = data.get("models", [])
    if args.max:
        models = models[: args.max]

    manifest_file, progress_file, failed_file = get_run_paths(output_dir, brand_slug)
    progress = load_progress(progress_file)

    tracker = ProgressTracker(
        progress_file=progress_file,
        checkpoint_every=args.checkpoint_every,
        checkpoint_interval=args.checkpoint_interval,
        completed=progress.get("completed", []),
        manifest=progress.get("manifest", {}),
    )

    r2_prefix = (args.r2_prefix or brand_slug or "watchcharts").strip("/")

    r2_bucket = args.r2_bucket or os.getenv("R2_BUCKET")
    r2_public_url = (args.r2_public_url or R2_PUBLIC_URL).rstrip("/")
    r2_endpoint = args.r2_endpoint or os.getenv("R2_ENDPOINT")
    if not r2_endpoint:
        account_id = os.getenv("R2_ACCOUNT_ID")
        if account_id:
            r2_endpoint = f"https://{account_id}.r2.cloudflarestorage.com"

    access_key = os.getenv("R2_ACCESS_KEY_ID") or os.getenv("AWS_ACCESS_KEY_ID")
    secret_key = os.getenv("R2_SECRET_ACCESS_KEY") or os.getenv("AWS_SECRET_ACCESS_KEY")

    upload_enabled = not args.no_upload
    if upload_enabled:
        missing = [
            name
            for name, value in (
                ("R2_BUCKET", r2_bucket),
                ("R2_ENDPOINT", r2_endpoint),
                ("R2_ACCESS_KEY_ID", access_key),
                ("R2_SECRET_ACCESS_KEY", secret_key),
            )
            if not value
        ]
        if missing:
            raise SystemExit(
                "Missing R2 config: "
                + ", ".join(missing)
                + ". Set env vars, or pass --env-file /path/to/.env, or export R2_ENV_FILE."
            )

    config = PipelineConfig(
        output_dir=output_dir,
        images_dir=images_dir,
        r2_prefix=r2_prefix,
        max_width=args.max_width,
        webp_quality=args.webp_quality,
        download_timeout=args.timeout,
        download_retries=args.retries,
        concurrency=args.concurrency,
        upload_concurrency=args.upload_concurrency,
        checkpoint_every=args.checkpoint_every,
        checkpoint_interval=args.checkpoint_interval,
        reuse_local=not args.no_reuse_local,
        detail_fallback=not args.no_detail_fallback,
        use_flaresolverr=USE_FLARESOLVERR and not args.no_flaresolverr,
        upload_enabled=upload_enabled,
        r2_bucket=r2_bucket,
        r2_public_url=r2_public_url,
    )

    max_connections = max(10, args.concurrency * 2)
    limits = httpx.Limits(max_connections=max_connections, max_keepalive_connections=max_connections)
    timeout = httpx.Timeout(args.timeout, connect=min(args.timeout, 10.0))

    async with httpx.AsyncClient(
        headers=DEFAULT_HEADERS.copy(),
        follow_redirects=True,
        limits=limits,
        timeout=timeout,
        http2=bool(h2),
    ) as client:
        flare_client = FlareSolverrClient() if config.use_flaresolverr else None
        if flare_client:
            flare_client.create_session()

        r2_client = None
        if upload_enabled:
            r2_client = build_r2_client(
                endpoint_url=r2_endpoint,
                access_key=access_key,
                secret_key=secret_key,
                max_connections=max(args.upload_concurrency * 2, 10),
            )

        queue: asyncio.Queue = asyncio.Queue()
        for model in models:
            queue.put_nowait(model)

        worker_count = min(args.concurrency, len(models)) or 1
        upload_sem = asyncio.Semaphore(max(1, args.upload_concurrency))
        workers = [
            asyncio.create_task(
                worker(
                    f"worker-{i}",
                    queue,
                    client,
                    flare_client,
                    tracker,
                    config,
                    r2_client,
                    upload_sem,
                )
            )
            for i in range(worker_count)
        ]

        try:
            await queue.join()
        finally:
            for _ in workers:
                queue.put_nowait(None)
            await asyncio.gather(*workers, return_exceptions=True)
            if flare_client:
                flare_client.destroy_session()

    await tracker.finalize(manifest_file, failed_file)

    print("\n" + "=" * 50)
    print(f"Completed: {len(tracker.completed)}/{len(models)}")
    print(f"Failed: {len(tracker.failed)}")
    print(f"Manifest saved to: {manifest_file}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Download + upload WatchCharts images (fast async)")
    parser.add_argument("--brand", type=str, help="Brand display name (e.g., Rolex)")
    parser.add_argument("--brand-slug", type=str, help="Brand slug for filenames (e.g., rolex)")
    parser.add_argument("--input", type=str, help="Path to WatchCharts brand JSON")
    parser.add_argument("--output-dir", type=str, help="Output directory for manifests")
    parser.add_argument("--images-dir", type=str, help="Local image cache directory")
    parser.add_argument("--r2-prefix", type=str, help="R2 key prefix (default: brand slug)")
    parser.add_argument("--r2-bucket", type=str, help="R2 bucket name (env R2_BUCKET)")
    parser.add_argument("--r2-endpoint", type=str, help="R2 endpoint URL (env R2_ENDPOINT)")
    parser.add_argument("--r2-public-url", type=str, help="Public URL base (env R2_PUBLIC_URL)")
    parser.add_argument("--env-file", type=str, help="Path to env file with R2 credentials")
    parser.add_argument("--max", type=int, help="Maximum number of models to process")
    parser.add_argument("--concurrency", type=int, default=24, help="Number of concurrent workers")
    parser.add_argument("--upload-concurrency", type=int, default=8, help="Max concurrent R2 uploads")
    parser.add_argument("--timeout", type=float, default=30.0, help="HTTP timeout in seconds")
    parser.add_argument("--retries", type=int, default=1, help="Download retry count")
    parser.add_argument("--max-width", type=int, default=MAX_WIDTH_DEFAULT, help="Max image width")
    parser.add_argument("--webp-quality", type=int, default=WEBP_QUALITY_DEFAULT, help="WebP quality")
    parser.add_argument("--checkpoint-every", type=int, default=CHECKPOINT_EVERY_DEFAULT, help="Save progress every N items")
    parser.add_argument("--checkpoint-interval", type=float, default=CHECKPOINT_INTERVAL_DEFAULT, help="Save progress at least every N seconds")
    parser.add_argument("--no-reuse-local", action="store_true", help="Ignore cached local images")
    parser.add_argument("--no-detail-fallback", action="store_true", help="Skip detail-page fallback for missing image_url")
    parser.add_argument("--no-flaresolverr", action="store_true", help="Disable FlareSolverr for detail fallback")
    parser.add_argument("--no-upload", action="store_true", help="Skip R2 upload")
    args = parser.parse_args()

    asyncio.run(run_async(args))


if __name__ == "__main__":
    main()
