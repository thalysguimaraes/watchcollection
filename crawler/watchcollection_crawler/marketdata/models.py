from dataclasses import dataclass, field
from datetime import date, datetime
from enum import Enum
from typing import List, Optional


class SnapshotSource(str, Enum):
    WATCHCHARTS_CSV = "watchcharts_csv"
    CHRONO24 = "chrono24"


@dataclass
class MarketSnapshot:
    watchcharts_id: str
    brand_slug: str
    reference: str
    as_of_date: date
    source: SnapshotSource
    currency: str = "USD"
    median_usd: Optional[int] = None
    min_usd: Optional[int] = None
    max_usd: Optional[int] = None
    listings_count: Optional[int] = None
    raw_json: Optional[str] = None
    id: Optional[int] = None
    created_at: Optional[datetime] = None

    def to_row(self) -> tuple:
        return (
            self.watchcharts_id,
            self.brand_slug,
            self.reference,
            self.as_of_date.isoformat(),
            self.source.value if isinstance(self.source, SnapshotSource) else self.source,
            self.currency,
            self.median_usd,
            self.min_usd,
            self.max_usd,
            self.listings_count,
            self.raw_json,
        )

    @classmethod
    def from_row(cls, row: tuple) -> "MarketSnapshot":
        return cls(
            id=row[0],
            watchcharts_id=row[1],
            brand_slug=row[2],
            reference=row[3],
            as_of_date=date.fromisoformat(row[4]),
            source=SnapshotSource(row[5]),
            currency=row[6],
            median_usd=row[7],
            min_usd=row[8],
            max_usd=row[9],
            listings_count=row[10],
            raw_json=row[11],
            created_at=datetime.fromisoformat(row[12]) if row[12] else None,
        )


@dataclass
class IngestRun:
    pipeline: str
    started_at: datetime
    finished_at: Optional[datetime] = None
    ok: bool = False
    rows_in: int = 0
    rows_out: int = 0
    errors: int = 0
    warnings: int = 0
    meta_json: Optional[str] = None
    run_id: Optional[int] = None

    @classmethod
    def from_row(cls, row: tuple) -> "IngestRun":
        return cls(
            run_id=row[0],
            pipeline=row[1],
            started_at=datetime.fromisoformat(row[2]),
            finished_at=datetime.fromisoformat(row[3]) if row[3] else None,
            ok=bool(row[4]),
            rows_in=row[5] or 0,
            rows_out=row[6] or 0,
            errors=row[7] or 0,
            warnings=row[8] or 0,
            meta_json=row[9],
        )


@dataclass
class IngestStats:
    rows_in: int = 0
    rows_out: int = 0
    errors: int = 0
    warnings: int = 0
    error_messages: List[str] = field(default_factory=list)
