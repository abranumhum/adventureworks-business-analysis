# AdventureWorks Business Analysis

SQL-first analysis of AdventureWorksDW sales: revenue drivers, year-over-year contribution, product concentration, customer segmentation, and gross margin. PostgreSQL produces the main analytical outputs; Python is used selectively for exploration and Pareto analysis; Excel is a separate management-report artifact.

## At a glance

- **60,398 order lines** and **27,659 distinct orders**
- **2010-12-29 to 2014-01-28**; 2014 is partial
- **SQL:** joins, CTEs, conditional aggregation, `NTILE`, ranking, cumulative windows
- **Python:** focused EDA, Pareto curve, segment profiling, four charts
- **Excel:** formula-driven KPI dashboard, four Excel Tables, conditional formatting, two charts

## Project structure

```text
sql/
  01_load.sql
  02_analysis.sql
notebooks/
  analysis.ipynb
excel/
  management_report.xlsx
charts/
  q1_revenue_drivers.png
  q3_pareto_products.png
  q4_customer_segments.png
  q5_revenue_vs_margin.png
scripts/
  load_csvs.py
  load_and_analyze.sh
README.md
```

The official Microsoft CSV files are downloaded by `load_csvs.py` when they are missing and are not committed to the repository.

## Quick start

Requires Python 3.11+ and PostgreSQL.

```bash
python3 -m venv .venv
.venv/bin/pip install pandas matplotlib "psycopg[binary]" nbconvert ipykernel

export PGHOST=127.0.0.1
export PGPORT=5432
export PGDATABASE=adventureworks
export PGUSER=postgres
export PGPASSWORD=your_password
export PSQL_BIN=psql
export PYTHON_BIN=.venv/bin/python

scripts/load_and_analyze.sh
.venv/bin/jupyter nbconvert --to notebook --execute --inplace notebooks/analysis.ipynb
```

The scripts use local-development defaults (`PGPORT=54320`, `PGDATABASE=olist`) only when variables are not set. Set the variables explicitly for your own database.

## Data model and grain

- `aw.fact_internet_sales`: one row per order line (`SalesOrderNumber` × `SalesOrderLineNumber`)
- `aw.dim_customer`: one row per customer key
- `aw.dim_product`: one row per product SKU
- product, category, date, and territory joins are many-to-one from the fact table
- AOV is calculated after aggregation to one row per order

Binary image columns are excluded from the analytical schema. `'NA'` placeholders in the source files are loaded as SQL `NULL`.

## Five analytical questions

### 1. What is associated with monthly revenue differences?

**Observation:** items per order stay near 2.1, while AOV and average item price vary more. December has the highest pooled monthly AOV at about **$1,154**.

**Interpretation:** the observed pattern was not driven by more items per order. Product mix and price are plausible explanations, but the aggregate does not separate them.

**Additional data needed:** promotions, list-price history, monthly product mix, and inventory availability.

### 2. Which category–territory combinations contributed to 2012→2013 growth?

**Observation:** Bikes account for most of the measured increase. Bikes–United States contributes **34.8%** of total change; Australia contributes **19.2%**.

**Hypothesis:** demand, launches, availability, or commercial activity may differ by territory.

**Additional data needed:** campaigns, launch dates, stockouts, channel mix, and regional market context.

### 3. How concentrated is product revenue?

**Observation:** the top 20% of sold product names generate **70.8%** of revenue. The top 20% of customers generate **66.4%**.

**Hypothesis:** leading products may deserve closer availability monitoring, but revenue concentration alone does not define stocking policy.

**Additional data needed:** stockouts, lead times, holding costs, demand volatility, and substitution.

### 4. What customer groups appear in an RFM-style segmentation?

SQL scores revenue, frequency, and recency with quintiles. A higher recency score means a more recent purchase. The notebook explicitly verifies the date ranges for all five recency quintiles.

**Observation:** the corrected At-Risk group contains customers with older last purchases and historically higher revenue or frequency. Champions combine high revenue, frequency, and recent activity.

**Hypothesis:** the At-Risk group may be suitable for a controlled reactivation test.

**Additional data needed:** contact consent, previous campaigns, cost per contact, control groups, and incremental revenue.

### 5. Which subcategories combine revenue and historical gross margin?

**Observation:** Road Bikes have the highest revenue (**$14.5M**) and a **38.1%** historical gross margin. Mountain Bikes have **$10.0M** revenue and **45.4%** margin. Several Accessories subcategories show **62.6%** margin on much smaller revenue bases.

**Hypothesis:** Road Bikes may warrant a price/cost investigation; Accessories may warrant a demand test. Margin percentage alone does not support assortment expansion.

**Additional data needed:** discounts, returns, freight allocation, overhead, price elasticity, inventory costs, and capacity.

## Important limitations

- AdventureWorks is a fictional sample dataset.
- 2014 contains only January; full-year YoY analysis therefore uses 2012 and 2013.
- Gross margin uses recorded product cost and does not include all operating costs.
- RFM labels are analytical rules, not proof of campaign responsiveness.
- Findings are descriptive; business actions are presented as hypotheses requiring further evidence.

## Outputs

- [`sql/02_analysis.sql`](sql/02_analysis.sql) — five main analytical outputs
- [`notebooks/analysis.ipynb`](notebooks/analysis.ipynb) — focused Python exploration
- [`excel/management_report.xlsx`](excel/management_report.xlsx) — standalone Excel report
- [`charts/`](charts/) — exported visualizations

Data source: [Microsoft SQL Server Samples — AdventureWorks](https://github.com/microsoft/sql-server-samples/tree/master/samples/databases/adventure-works/data-warehouse-install-script)
