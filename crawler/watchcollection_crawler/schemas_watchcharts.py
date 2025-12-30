from pydantic import BaseModel, Field
from typing import Optional, List
from datetime import datetime
from enum import Enum


class MovementType(str, Enum):
    AUTOMATIC = "automatic"
    MANUAL = "manual"
    QUARTZ = "quartz"


class CaseSpecs(BaseModel):
    diameter_mm: Optional[float] = None
    thickness_mm: Optional[float] = None
    material: Optional[str] = None
    bezel_material: Optional[str] = None
    crystal: Optional[str] = None
    water_resistance_m: Optional[int] = None
    lug_width_mm: Optional[float] = None
    dial_color: Optional[str] = None
    dial_numerals: Optional[str] = None


class MovementSpecs(BaseModel):
    type: Optional[str] = None
    caliber: Optional[str] = None
    power_reserve_hours: Optional[int] = None
    frequency_bph: Optional[int] = None
    jewels_count: Optional[int] = None


class MarketPriceHistoryPoint(BaseModel):
    timestamp: int
    price: Optional[float] = None
    min_price: Optional[float] = None
    max_price: Optional[float] = None


class MarketPriceHistory(BaseModel):
    region_id: int
    variation_id: int
    key: str
    currency: Optional[str] = None
    points: List[MarketPriceHistoryPoint] = Field(default_factory=list)
    max_time: Optional[int] = None
    chart_id: Optional[str] = None
    source: str = Field(default="watchcharts")


class WatchChartsModelDTO(BaseModel):
    watchcharts_id: str = Field(description="WatchCharts UUID")
    reference: str = Field(description="Reference/model number")
    reference_aliases: List[str] = Field(default_factory=list, description="Alternative reference formats")
    full_name: str = Field(description="Full marketing name")

    brand: str
    collection: Optional[str] = None
    nickname: Optional[str] = None
    style: Optional[str] = None

    year_introduced: Optional[int] = None
    year_discontinued: Optional[int] = None
    is_current: Optional[bool] = True

    case: Optional[CaseSpecs] = None
    movement: Optional[MovementSpecs] = None
    complications: List[str] = Field(default_factory=list)
    features: List[str] = Field(default_factory=list)

    market_price_usd: Optional[int] = None
    retail_price_usd: Optional[int] = None
    price_trend: Optional[str] = None
    market_price_history: Optional[MarketPriceHistory] = None

    watchcharts_url: str
    image_url: Optional[str] = None


class WatchChartsBrandCatalog(BaseModel):
    brand: str
    brand_slug: str
    models: List[WatchChartsModelDTO]
    crawled_at: datetime = Field(default_factory=datetime.utcnow)
    source: str = Field(default="watchcharts")
    total_available: Optional[int] = None
    entry_url: Optional[str] = None
