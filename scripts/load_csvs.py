#!/usr/bin/env python3
"""Load AdventureWorksDW CSVs into PostgreSQL via psycopg (v3) + pandas.

All CSVs are header-less and pipe-delimited.
Binary blob columns (DimProduct.LargePhoto, DimSalesTerritory.SalesTerritoryImage)
and analysis-irrelevant columns are dropped. 'NA' placeholders -> NULL.
"""
from __future__ import annotations
import csv
import io
import os
import sys
import urllib.request
from pathlib import Path

import psycopg
from psycopg import sql

RAW = Path(__file__).resolve().parents[1] / "data" / "raw"
SOURCE_BASE_URL = (
    "https://raw.githubusercontent.com/microsoft/sql-server-samples/master/"
    "samples/databases/adventure-works/data-warehouse-install-script/"
)

# Full CSV column order per table (from instawdbdw.sql BULK INSERT), lowercase.
CSV_COLUMNS = {
    "DimProductCategory": [
        "productcategorykey", "productcategoryalternatekey",
        "englishproductcategoryname", "spanishproductcategoryname",
        "frenchproductcategoryname",
    ],
    "DimProductSubcategory": [
        "productsubcategorykey", "productsubcategoryalternatekey",
        "englishproductsubcategoryname", "spanishproductsubcategoryname",
        "frenchproductsubcategoryname", "productcategorykey",
    ],
    "DimSalesTerritory": [
        "salesterritorykey", "salesterritoryalternatekey",
        "salesterritoryregion", "salesterritorycountry", "salesterritorygroup",
        "salesterritoryimage",
    ],
    "DimProduct": [
        "productkey", "productalternatekey", "productsubcategorykey",
        "weightunitmeasurecode", "sizeunitmeasurecode",
        "englishproductname", "spanishproductname", "frenchproductname",
        "standardcost", "finishedgoodsflag", "color",
        "safetystocklevel", "reorderpoint", "listprice", "size", "sizerange",
        "weight", "daystomanufacture", "productline", "dealerprice", "class", "style",
        "modelname", "largephoto", "englishdescription", "frenchdescription",
        "chinesedescription", "arabicdescription", "hebrewdescription", "thaidescription",
        "germandescription", "japanesedescription", "turkishdescription",
        "startdate", "enddate", "status",
    ],
    "DimDate": [
        "datekey", "fulldatealternatekey", "daynumberofweek", "englishdayofweek",
        "spanishdayofweek", "frenchdayofweek", "daynumberofmonth", "daynumberofyear",
        "weeknumberofyear", "englishmonthname", "spanishmonthname", "frenchmonthname",
        "monthnumberofyear", "calendarquarter", "calendaryear", "calendarsemester",
        "fiscalquarter", "fiscalyear", "fiscalSemester",
    ],
    "DimCustomer": [
        "customerkey", "geographykey", "customeralternatekey", "title", "firstname",
        "middlename", "lastname", "namesstyle", "birthdate", "maritalstatus", "suffix",
        "gender", "emailaddress", "yearlyincome", "totalchildren", "numberchildrenathome",
        "englisheducation", "spanisheducation", "frencheducation", "englishoccupation",
        "spanishoccupation", "frenchoccupation", "houseownerflag", "numbercarsowned",
        "addressline1", "addressline2", "phone", "datefirstpurchase", "commutedistance",
    ],
    "FactInternetSales": [
        "productkey", "orderdatekey", "duedatekey", "shipdatekey", "customerkey",
        "promotionkey", "currencykey", "salesterritorykey", "salesordernumber",
        "salesorderlinenumber", "revisionnumber", "orderquantity", "unitprice",
        "extendedamount", "unitpricediscountpct", "discountamount", "productstandardcost",
        "totalproductcost", "salesamount", "taxamt", "freight", "carriertrackingnumber",
        "customerponumber", "orderdate", "duedate", "shipdate",
    ],
}

# Columns to drop (binary blob / not in destination schema)
DROP_COLS = {
    "DimProduct": {"largephoto"},
    "DimSalesTerritory": {"salesterritoryalternatekey", "salesterritoryimage"},
    "DimProductCategory": {"productcategoryalternatekey"},
    "DimProductSubcategory": {"productsubcategoryalternatekey"},
    "DimDate": {"fulldatealternatekey", "spanishdayofweek", "frenchdayofweek",
                "spanishmonthname", "frenchmonthname", "fiscalSemester"},
    "DimCustomer": {"middlename", "suffix", "addressline2"},
    "FactInternetSales": {"duedatekey", "shipdatekey", "carriertrackingnumber",
                          "customerponumber", "duedate", "shipdate",
                          "promotionkey", "currencykey"},
}

TABLE_TARGET = {
    "DimProductCategory": "aw.dim_product_category",
    "DimProductSubcategory": "aw.dim_product_subcategory",
    "DimSalesTerritory": "aw.dim_sales_territory",
    "DimProduct": "aw.dim_product",
    "DimDate": "aw.dim_date",
    "DimCustomer": "aw.dim_customer",
    "FactInternetSales": "aw.fact_internet_sales",
}


def read_rows(name: str) -> tuple[list[str], list[list]]:
    """Read a header-less, pipe-delimited CSV, returning (cols, rows).

    cols = schema column names (CSV_COLUMNS minus DROP_COLS).
    rows = list of values aligned to cols. Handles embedded pipes in LargePhoto
    by parsing the CSV row first, then truncating to the expected column count.
    """
    path = RAW / f"{name}.csv"
    with open(path, "rb") as f:
        head = f.read(2)
    enc = "utf-16" if head in (b"\xff\xfe", b"\xfe\xff") else "utf-8"
    with open(path, encoding=enc) as f:
        data = f.read().replace("\x00", "")

    csv_cols = CSV_COLUMNS[name]
    drop = DROP_COLS.get(name, set())
    keep_idx = [i for i, c in enumerate(csv_cols) if c not in drop]
    cols = [csv_cols[i] for i in keep_idx]

    reader = csv.reader(io.StringIO(data), delimiter="|", quotechar='"')
    out: list[list] = []
    for r in reader:
        # Truncate to CSV width (handles LargePhoto base64 with extra pipes)
        if len(r) > len(csv_cols):
            r = r[: len(csv_cols)]
        # Pad if short (some rows may have fewer fields)
        if len(r) < len(csv_cols):
            r = r + [""] * (len(csv_cols) - len(r))
        out.append([_clean(r[i]) for i in keep_idx])
    return cols, out


def _clean(val: str) -> str:
    """Convert 'NA' placeholder to empty string (NULL for COPY)."""
    v = val.strip()
    return "" if v == "NA" else val


def load_table(conn, table: str, cols: list[str], rows: list[list]) -> None:
    """Fast bulk load using psycopg COPY."""
    if not rows:
        print(f"  {table}: 0 rows")
        return
    buf = io.StringIO()
    writer = csv.writer(buf, delimiter="\t", quoting=csv.QUOTE_MINIMAL)
    for r in rows:
        writer.writerow(r)
    buf.seek(0)

    col_list = sql.SQL(", ").join(sql.Identifier(c) for c in cols)
    parts = table.split(".")
    tbl = sql.SQL("{}.{}").format(sql.Identifier(parts[0]), sql.Identifier(parts[1]))
    query_str = sql.SQL("COPY {} ({}) FROM STDIN WITH (FORMAT csv, DELIMITER E'\\t', NULL '')")\
        .format(tbl, col_list).as_string(conn)

    with conn.cursor() as cur:
        with cur.copy(query_str) as copy:
            copy.write(buf.read())
    conn.commit()
    print(f"  {table}: {len(rows)} rows loaded")


def ensure_source_files() -> None:
    """Download the official Microsoft CSVs only when they are missing."""
    RAW.mkdir(parents=True, exist_ok=True)
    for name in TABLE_TARGET:
        path = RAW / f"{name}.csv"
        if path.exists():
            continue
        url = SOURCE_BASE_URL + path.name
        print(f"  downloading {path.name}")
        urllib.request.urlretrieve(url, path)


def main() -> int:
    ensure_source_files()
    conn = psycopg.connect(
        host=os.environ.get("PGHOST", "127.0.0.1"),
        port=os.environ.get("PGPORT", "54320"),
        dbname=os.environ.get("PGDATABASE", "olist"),
        user=os.environ.get("PGUSER", "postgres"),
        password=os.environ.get("PGPASSWORD", "postgres"),
    )

    for name, target in TABLE_TARGET.items():
        cols, rows = read_rows(name)
        load_table(conn, target, cols, rows)

    conn.close()
    print("All tables loaded.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
