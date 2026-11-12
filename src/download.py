"""Download source data files into data/raw/."""

from pathlib import Path

import requests

RAW_DIR = Path(__file__).resolve().parent.parent / "data" / "raw"
CPI_URL = "https://storage.dosm.gov.my/cpi/cpi_2d_state.parquet"
PRICECATCHER_URL = "https://storage.data.gov.my/pricecatcher/pricecatcher_{month}.parquet"

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

    Use this for files whose name fixes their contents, such as one month
    of PriceCatcher. Delete the file to force a fresh download.
    """
    if destination.exists():
        print(f"Skipped {destination.name} (already downloaded)")
        return
    download_file(url, destination)


if __name__ == "__main__":
    # CPI is one file that gains a new month each release, so always refresh it.
    download_file(CPI_URL, RAW_DIR / "cpi_2d_state.parquet")

    for month in PRICECATCHER_MONTHS:
        download_if_missing(
            PRICECATCHER_URL.format(month=month),
            RAW_DIR / f"pricecatcher_{month}.parquet",
        )
