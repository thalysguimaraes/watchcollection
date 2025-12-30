from pydantic import BaseModel, Field
from typing import Optional, List
from datetime import datetime


class WatchModelDTO(BaseModel):
    reference: str = Field(description="Reference/model number (e.g., 116610LN)")
    display_name: str = Field(description="Marketing name (e.g., Submariner Date)")
    collection: Optional[str] = Field(None, description="Collection/family (e.g., Submariner)")
    production_year_start: Optional[int] = Field(None, description="Year production started")
    production_year_end: Optional[int] = Field(None, description="Year production ended, None if still in production")
    case_diameter_mm: Optional[float] = Field(None, description="Case diameter in millimeters")
    case_material: Optional[str] = Field(None, description="Case material (e.g., Stainless Steel, Gold)")
    movement_type: Optional[str] = Field(None, description="Automatic, Manual Wind, or Quartz")
    caliber: Optional[str] = Field(None, description="Movement caliber/reference")
    water_resistance_m: Optional[int] = Field(None, description="Water resistance in meters")
    retail_price_usd: Optional[int] = Field(None, description="Current retail price in USD")


class BrandInfo(BaseModel):
    id: str = Field(description="Lowercase brand identifier")
    name: str = Field(description="Official brand name")
    country: str = Field(description="Country of origin")
    tier: str = Field(description="Brand tier: holy_trinity, luxury, premium, upper_mid, independent, accessible")


class BrandCatalog(BaseModel):
    brand: BrandInfo
    models: List[WatchModelDTO]
    crawled_at: datetime = Field(default_factory=datetime.utcnow)
    source: str = Field(default="chrono24")


class WatchModelsResponse(BaseModel):
    """Wrapper for Firecrawl agent response"""
    models: List[WatchModelDTO] = Field(description="List of watch models found")


class CrawlResult(BaseModel):
    success: bool
    brand: str
    models_count: int
    credits_used: Optional[int] = None
    error: Optional[str] = None
