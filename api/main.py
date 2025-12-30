from fastapi import FastAPI, HTTPException, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from pydantic import BaseModel
from typing import Dict, List, Optional, Tuple
from email.utils import formatdate
import json
import os
from pathlib import Path
import threading

app = FastAPI(
    title="Watch Catalog API",
    description="API for watch collection catalog data",
    version="2.0.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.add_middleware(GZipMiddleware, minimum_size=1024)

DATA_DIR = Path(__file__).parent / "data"


class BrandInfo(BaseModel):
    id: str
    name: str
    country: Optional[str] = None
    tier: Optional[str] = None


class MarketPrice(BaseModel):
    min_usd: Optional[int] = None
    max_usd: Optional[int] = None
    median_usd: Optional[int] = None
    listings: Optional[int] = None
    updated_at: Optional[str] = None


class MarketPriceHistory(BaseModel):
    source: Optional[str] = None
    points: Optional[List[List[float]]] = None


class CaseInfo(BaseModel):
    diameter_mm: Optional[float] = None
    thickness_mm: Optional[float] = None
    material: Optional[str] = None
    bezel_material: Optional[str] = None
    crystal: Optional[str] = None
    water_resistance_m: Optional[int] = None
    lug_width_mm: Optional[float] = None
    dial_color: Optional[str] = None
    dial_numerals: Optional[str] = None


class MovementInfo(BaseModel):
    type: Optional[str] = None
    caliber: Optional[str] = None
    power_reserve_hours: Optional[int] = None
    frequency_bph: Optional[int] = None
    jewels_count: Optional[int] = None


class WatchModelInfo(BaseModel):
    reference: str
    reference_aliases: List[str] = []
    display_name: str
    collection: Optional[str] = None
    style: Optional[str] = None
    production_year_start: Optional[int] = None
    production_year_end: Optional[int] = None
    case: Optional[CaseInfo] = None
    movement: Optional[MovementInfo] = None
    complications: List[str] = []
    features: List[str] = []
    retail_price_usd: Optional[int] = None
    catalog_image_url: Optional[str] = None
    market_price: Optional[MarketPrice] = None
    market_price_history: Optional[MarketPriceHistory] = None
    watchcharts_id: Optional[str] = None
    watchcharts_url: Optional[str] = None
    is_current: Optional[bool] = None


class BrandWithModels(BaseModel):
    id: str
    name: str
    country: Optional[str] = None
    tier: Optional[str] = None
    models: List[WatchModelInfo]


class CatalogResponse(BaseModel):
    version: str
    brands: List[BrandWithModels]


class BrandsResponse(BaseModel):
    brands: List[BrandInfo]


class CatalogStore:
    def __init__(self, data_dir: Path) -> None:
        self._bundle_file = data_dir / "catalog_bundle.json"
        self._lock = threading.Lock()
        self._signature: Optional[Tuple[int, int]] = None
        self._catalog_response: CatalogResponse = CatalogResponse(version="0.0.0", brands=[])
        self._brands_response: BrandsResponse = BrandsResponse(brands=[])
        self._brands_by_id: Dict[str, BrandWithModels] = {}
        self._brand_models_by_id: Dict[str, List[WatchModelInfo]] = {}
        self._models_by_reference: Dict[str, WatchModelInfo] = {}
        self._search_index: List[Tuple[str, str, WatchModelInfo, str]] = []
        self._etag: Optional[str] = None
        self._last_modified: Optional[str] = None

    def refresh(self) -> None:
        self._ensure_loaded(force=True)

    def get_catalog(self) -> CatalogResponse:
        self._ensure_loaded()
        return self._catalog_response

    def get_brands(self) -> BrandsResponse:
        self._ensure_loaded()
        return self._brands_response

    def get_brand(self, brand_id: str) -> Optional[BrandWithModels]:
        self._ensure_loaded()
        return self._brands_by_id.get(brand_id)

    def get_brand_models(self, brand_id: str) -> Optional[List[WatchModelInfo]]:
        self._ensure_loaded()
        return self._brand_models_by_id.get(brand_id)

    def get_model(self, reference: str) -> Optional[WatchModelInfo]:
        self._ensure_loaded()
        return self._models_by_reference.get(reference)

    def search(self, query: str, limit: int) -> List[dict]:
        self._ensure_loaded()
        lowered = query.lower()
        results: List[dict] = []
        for brand_id, brand_name, model, search_text in self._search_index:
            if lowered in search_text:
                payload = model.model_dump()
                payload["brand_id"] = brand_id
                payload["brand_name"] = brand_name
                results.append(payload)
                if len(results) >= limit:
                    break
        return results

    def cache_headers(self, max_age: int) -> Dict[str, str]:
        self._ensure_loaded()
        headers = {"Cache-Control": f"public, max-age={max_age}"}
        if self._etag:
            headers["ETag"] = self._etag
        if self._last_modified:
            headers["Last-Modified"] = self._last_modified
        return headers

    def _ensure_loaded(self, force: bool = False) -> None:
        try:
            stat = self._bundle_file.stat()
        except FileNotFoundError:
            with self._lock:
                if self._signature is not None or force:
                    self._apply_catalog({"version": "0.0.0", "brands": []}, None, None, None)
            return

        signature = (stat.st_mtime_ns, stat.st_size)
        with self._lock:
            if not force and signature == self._signature:
                return
            try:
                with open(self._bundle_file, "r", encoding="utf-8") as f:
                    catalog = json.load(f)
            except Exception as exc:
                print(f"Failed to load catalog bundle: {exc}")
                if self._signature is None:
                    self._apply_catalog({"version": "0.0.0", "brands": []}, None, None, None)
                return

            etag = f'W/"{stat.st_mtime_ns}-{stat.st_size}"'
            last_modified = formatdate(stat.st_mtime, usegmt=True)
            self._apply_catalog(catalog, signature, etag, last_modified)

    def _build_search_text(self, brand_name: str, model: WatchModelInfo) -> str:
        parts = [
            brand_name,
            model.display_name,
            model.reference,
            model.collection,
            model.style,
        ]
        parts.extend(model.reference_aliases)
        if model.case:
            parts.extend([
                model.case.material,
                model.case.dial_color,
            ])
        if model.movement:
            parts.extend([
                model.movement.caliber,
                model.movement.type,
            ])
        parts.extend(model.complications)
        parts.extend(model.features)
        return " ".join(part for part in parts if part).lower()

    def _apply_catalog(
        self,
        catalog: dict,
        signature: Optional[Tuple[int, int]],
        etag: Optional[str],
        last_modified: Optional[str],
    ) -> None:
        brands_data = catalog.get("brands", [])
        brands = [BrandWithModels(**b) for b in brands_data]

        brand_models_by_id: Dict[str, List[WatchModelInfo]] = {}
        models_by_reference: Dict[str, WatchModelInfo] = {}
        search_index: List[Tuple[str, str, WatchModelInfo, str]] = []

        for brand in brands:
            brand_models_by_id[brand.id] = brand.models
            for model in brand.models:
                models_by_reference[model.reference] = model
                for alias in model.reference_aliases:
                    if alias not in models_by_reference:
                        models_by_reference[alias] = model
                search_text = self._build_search_text(brand.name, model)
                search_index.append((brand.id, brand.name, model, search_text))

        brands_response = BrandsResponse(
            brands=[
                BrandInfo(
                    id=brand.id,
                    name=brand.name,
                    country=brand.country,
                    tier=brand.tier,
                )
                for brand in brands
            ]
        )

        self._signature = signature
        self._catalog_response = CatalogResponse(
            version=catalog.get("version", "0.0.0"),
            brands=brands,
        )
        self._brands_response = brands_response
        self._brands_by_id = {brand.id: brand for brand in brands}
        self._brand_models_by_id = brand_models_by_id
        self._models_by_reference = models_by_reference
        self._search_index = search_index
        self._etag = etag
        self._last_modified = last_modified


catalog_store = CatalogStore(DATA_DIR)


@app.on_event("startup")
def preload_catalog() -> None:
    catalog_store.refresh()


def not_modified_response(
    request: Request,
    etag: Optional[str],
    last_modified: Optional[str],
    headers: Dict[str, str],
) -> Optional[Response]:
    if etag and request.headers.get("if-none-match") == etag:
        return Response(status_code=304, headers=headers)
    if last_modified and request.headers.get("if-modified-since") == last_modified:
        return Response(status_code=304, headers=headers)
    return None


@app.get("/")
async def root():
    return {"status": "ok", "service": "watch-catalog-api"}


@app.get("/health")
async def health():
    return {"status": "healthy"}


@app.get("/config")
async def get_config():
    return {"anthropic_api_key": os.environ.get("ANTHROPIC_API_KEY", "")}


@app.get("/catalog", response_model=CatalogResponse)
async def get_catalog(request: Request, response: Response):
    headers = catalog_store.cache_headers(max_age=3600)
    etag = headers.get("ETag")
    last_modified = headers.get("Last-Modified")
    not_modified = not_modified_response(
        request,
        etag,
        last_modified,
        headers,
    )
    if not_modified:
        return not_modified
    response.headers.update(headers)
    return catalog_store.get_catalog()


@app.get("/catalog/version")
async def get_catalog_version(request: Request, response: Response):
    headers = catalog_store.cache_headers(max_age=300)
    etag = headers.get("ETag")
    last_modified = headers.get("Last-Modified")
    not_modified = not_modified_response(
        request,
        etag,
        last_modified,
        headers,
    )
    if not_modified:
        return not_modified
    response.headers.update(headers)
    return {"version": catalog_store.get_catalog().version}


@app.get("/brands", response_model=BrandsResponse)
async def get_brands():
    return catalog_store.get_brands()


@app.get("/brands/{brand_id}", response_model=BrandWithModels)
async def get_brand(brand_id: str):
    brand = catalog_store.get_brand(brand_id)
    if brand:
        return brand
    raise HTTPException(status_code=404, detail=f"Brand '{brand_id}' not found")


@app.get("/brands/{brand_id}/models", response_model=List[WatchModelInfo])
async def get_brand_models(brand_id: str):
    models = catalog_store.get_brand_models(brand_id)
    if models is not None:
        return models
    raise HTTPException(status_code=404, detail=f"Brand '{brand_id}' not found")


@app.get("/models/{reference}", response_model=WatchModelInfo)
async def get_model(reference: str):
    model = catalog_store.get_model(reference)
    if model:
        return model
    raise HTTPException(status_code=404, detail=f"Model '{reference}' not found")


@app.get("/search")
async def search_models(q: str, limit: int = 20):
    results = catalog_store.search(q, limit)
    return {"query": q, "count": len(results), "results": results}
