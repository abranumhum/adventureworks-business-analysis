#!/usr/bin/env bash
set -euo pipefail

# AdventureWorksDW load + analysis pipeline.
# Requires a reachable PostgreSQL with psql on PGHOST:PGPORT/PGDATABASE.
# PGUSER / PGPASSWORD env vars should be set (use .pgpass if preferred).

PSQL_BIN="${PSQL_BIN:-psql}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "Loading schema..."
"$PSQL_BIN" -v ON_ERROR_STOP=1 -f "$ROOT_DIR/sql/01_load.sql"

echo "Loading official CSVs via Python (psycopg)..."
"$PYTHON_BIN" "$ROOT_DIR/scripts/load_csvs.py"

echo "Building analytical layer..."
"$PSQL_BIN" -v ON_ERROR_STOP=1 -f "$ROOT_DIR/sql/02_analysis.sql"

echo "=== Pipeline complete ==="
"$PSQL_BIN" -c "SELECT count(*) AS fact_rows FROM aw.fact_internet_sales"
"$PSQL_BIN" -c "
    SELECT count(DISTINCT p.englishproductname) AS sold_product_names
    FROM aw.fact_internet_sales f
    JOIN aw.dim_product p ON p.productkey = f.productkey
"
