import re
import unicodedata


def slugify(value: str, fallback: str = "watchcharts") -> str:
    if not value:
        return fallback
    normalized = unicodedata.normalize("NFKD", value)
    ascii_value = "".join(ch for ch in normalized if not unicodedata.combining(ch))
    slug = re.sub(r"[^a-z0-9]+", "_", ascii_value.lower()).strip("_")
    return slug or fallback
