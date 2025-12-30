import os
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parents[2]

OUTPUT_DIR = Path(os.getenv("WATCHCOLLECTION_OUTPUT_DIR", str(ROOT_DIR / "output")))
WATCHCHARTS_OUTPUT_DIR = Path(
    os.getenv("WATCHCHARTS_OUTPUT_DIR", str(ROOT_DIR / "output_watchcharts"))
)
WATCHCHARTS_IMAGES_DIR = Path(
    os.getenv("WATCHCHARTS_IMAGES_DIR", str(ROOT_DIR / "images_cache"))
)

API_DATA_DIR = Path(
    os.getenv(
        "WATCHCOLLECTION_API_DATA_DIR",
        str(ROOT_DIR.parent / "api" / "data"),
    )
)
