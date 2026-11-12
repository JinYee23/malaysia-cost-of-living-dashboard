"""Download source data files into data/raw/."""

from pathlib import Path

import requests

RAW_DIR = Path(__file__).resolve().parent.parent / "data" / "raw"
CPI_URL = "https://storage.dosm.gov.my/cpi/cpi_2d_state.parquet"
PRICECATCHER_URL = "https://storage.data.gov.my/pricecatcher/pricecatcher_{month}.parquet"
LOOKUP_ITEM_URL = "https://storage.data.gov.my/pricecatcher/lookup_item.parquet"
LOOKUP_PREMISE_URL = "https://storage.data.gov.my/pricecatcher/lookup_premise.parquet"
MCOICOP_URL = "https://storage.dosm.gov.my/dictionaries/mcoicop.parquet"

# Finished months to download. Add months here to scale up.
PRICECATCHER_MONTHS = ["2026-08", "2026-09", "2026-10"]


def download_file(url, destination):
    """Save the file at url to destination, stopping if the request fails."""
    response = requests.get(url, timeout=60)
    response.raise_for_status()
    destination.write_bytes(response.content)
    print(f"Saved {destination.name} ({destination.stat().st_size:,} bytes)")


def download_if_missing(url, destination):
    """Download only if the file is not already in data/raw/.

    Use this for files that rarely or never change, such as one month
    of PriceCatcher. Delete the file to force a fresh download.
    """
    if destination.exists():
        print(f"Skipped {destination.name} (already downloaded)")
        return
    download_file(url, destination)


if __name__ == "__main__":
    # Always refresh: same filename, contents updated over time.
    download_file(CPI_URL, RAW_DIR / "cpi_2d_state.parquet")
    download_file(LOOKUP_ITEM_URL, RAW_DIR / "lookup_item.parquet")
    download_file(LOOKUP_PREMISE_URL, RAW_DIR / "lookup_premise.parquet")

    # Skip if present: the CPI category list rarely changes.
    download_if_missing(MCOICOP_URL, RAW_DIR / "mcoicop.parquet")

    for month in PRICECATCHER_MONTHS:
        download_if_missing(
            PRICECATCHER_URL.format(month=month),
            RAW_DIR / f"pricecatcher_{month}.parquet",
        )
