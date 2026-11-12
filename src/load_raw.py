"""Load the files in data/raw/ into the raw schema in PostgreSQL.

Each table is replaced on every run: TRUNCATE empties it and COPY refills it,
inside one transaction, so a failed load leaves the previous data in place.
Run sql/02_create_raw_tables.sql first to create the tables.
"""

import io
import time
from pathlib import Path

import pandas as pd
import psycopg
from dotenv import load_dotenv

PROJECT_DIR = Path(__file__).resolve().parent.parent
RAW_DIR = PROJECT_DIR / "data" / "raw"
CHUNK_ROWS = 500_000  # rows converted to CSV at a time, to limit memory use


def read_prices():
    """Combine every monthly PriceCatcher file, recording which file each row came from."""
    frames = []
    for path in sorted(RAW_DIR.glob("pricecatcher_*.parquet")):
        frames.append(pd.read_parquet(path).assign(source_file=path.name))
    return pd.concat(frames, ignore_index=True)


def replace_table(conn, table, df):
    """Empty the table, then fill it from df with COPY, all in one transaction."""
    columns = ", ".join(f'"{col}"' for col in df.columns)
    start = time.perf_counter()

    with conn.transaction(), conn.cursor() as cur:
        cur.execute(f"TRUNCATE {table}")
        with cur.copy(f"COPY {table} ({columns}) FROM STDIN (FORMAT csv)") as copy:
            for i in range(0, len(df), CHUNK_ROWS):
                buffer = io.StringIO()
                df.iloc[i : i + CHUNK_ROWS].to_csv(buffer, index=False, header=False)
                copy.write(buffer.getvalue())
        cur.execute(f"SELECT count(*) FROM {table}")
        loaded = cur.fetchone()[0]

    seconds = time.perf_counter() - start
    print(f"{table}: {loaded:,} rows in {seconds:.1f}s")
    if loaded != len(df):
        raise RuntimeError(f"{table}: loaded {loaded:,} rows but the file has {len(df):,}")


if __name__ == "__main__":
    load_dotenv(PROJECT_DIR / ".env")  # PG* settings; psycopg reads them automatically

    sources = {
        "raw.prices": read_prices,
        "raw.cpi": lambda: pd.read_parquet(RAW_DIR / "cpi_2d_state.parquet"),
        "raw.lookup_item": lambda: pd.read_parquet(RAW_DIR / "lookup_item.parquet"),
        "raw.lookup_premise": lambda: pd.read_parquet(RAW_DIR / "lookup_premise.parquet"),
        "raw.mcoicop": lambda: pd.read_parquet(RAW_DIR / "mcoicop.parquet"),
    }

    with psycopg.connect() as conn:
        for table, read in sources.items():
            replace_table(conn, table, read())
