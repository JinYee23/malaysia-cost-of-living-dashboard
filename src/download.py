"""Download source data files into data/raw/."""

from pathlib import Path

import requests

RAW_DIR = Path(__file__).resolve().parent.parent / "data" / "raw"
CPI_URL = "https://storage.dosm.gov.my/cpi/cpi_2d_state.parquet"


def download_file(url, destination):
    """Save the file at url to destination, stopping if the request fails."""
    response = requests.get(url, timeout=60)
    response.raise_for_status()
    destination.write_bytes(response.content)


if __name__ == "__main__":
    destination = RAW_DIR / "cpi_2d_state.parquet"
    download_file(CPI_URL, destination)
    print(f"Saved {destination.name} ({destination.stat().st_size:,} bytes)")
