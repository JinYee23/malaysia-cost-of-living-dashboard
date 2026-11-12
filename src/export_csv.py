"""Export the mart and report tables to outputs/csv/ as a backup for Power BI and other tools.

Uses COPY ... TO STDOUT, the reverse of the loader, so even the 22M-row price table
exports quickly. Each file is overwritten on every run.
fact_prices.csv is too large for GitHub, so .gitignore keeps it on this computer only.
"""

import time
from pathlib import Path

import psycopg
from dotenv import load_dotenv

PROJECT_DIR = Path(__file__).resolve().parent.parent
OUT_DIR = PROJECT_DIR / "outputs" / "csv"

# (schema, table): mart dimensions first, then facts, then the saved analysis results
TABLES = [
    ("mart", "dim_date"),
    ("mart", "dim_state"),
    ("mart", "dim_division"),
    ("mart", "dim_item"),
    ("mart", "dim_premise"),
    ("mart", "fact_cpi"),
    ("mart", "fact_prices"),
    ("report", "q2_item_change"),
    ("report", "q3_type_vs_cell"),
    ("report", "basket_item"),
]


def count_data_lines(path):
    """Count lines in the file, minus the header, reading in chunks to save memory."""
    lines = 0
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            lines += chunk.count(b"\n")
    return lines - 1


def export_table(cur, schema, table):
    """Write <schema>.<table> to a CSV with a header row, then check its row count.

    Mart tables keep their own name (dim_item.csv); report tables get a prefix
    (report_q2_item_change.csv) so it is clear they are analysis results.
    """
    path = OUT_DIR / (f"{table}.csv" if schema == "mart" else f"{schema}_{table}.csv")
    start = time.perf_counter()

    with path.open("wb") as f:
        with cur.copy(f"COPY {schema}.{table} TO STDOUT (FORMAT csv, HEADER)") as copy:
            for data in copy:
                f.write(data)

    table_rows = cur.execute(f"SELECT count(*) FROM {schema}.{table}").fetchone()[0]
    file_rows = count_data_lines(path)
    size_mb = path.stat().st_size / 1024 / 1024
    seconds = time.perf_counter() - start
    print(f"{path.name}: {file_rows:,} rows, {size_mb:,.1f} MB in {seconds:.1f}s")
    if file_rows != table_rows:
        raise RuntimeError(f"{path.name}: wrote {file_rows:,} rows but {schema}.{table} has {table_rows:,}")


if __name__ == "__main__":
    load_dotenv(PROJECT_DIR / ".env")  # PG* settings; psycopg reads them automatically
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    with psycopg.connect() as conn, conn.cursor() as cur:
        for schema, table in TABLES:
            export_table(cur, schema, table)
