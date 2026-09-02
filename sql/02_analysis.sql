-- 02_analysis.sql
-- Five business questions analyzed on the AdventureWorksDW analytical layer.
-- Run after 01_load.sql + load_csvs.py have populated the aw/ schemas.
BEGIN;

-- =====================================================================
-- Analytical fact table (one row per order line, denormalized)
-- =====================================================================
DROP TABLE IF EXISTS analytics.fact_sales CASCADE;
DROP TABLE IF EXISTS analytics.product_dim CASCADE;
DROP TABLE IF EXISTS analytics.q1_revenue_drivers CASCADE;
DROP TABLE IF EXISTS analytics.q2_contribution_to_change CASCADE;
DROP TABLE IF EXISTS analytics.q3_pareto_concentration CASCADE;
DROP TABLE IF EXISTS analytics.q4_customer_segments CASCADE;
DROP TABLE IF EXISTS analytics.q5_revenue_vs_margin CASCADE;
CREATE TABLE analytics.fact_sales AS
SELECT
    f.productkey,
    f.customerkey,
    f.salesterritorykey,
    f.salesordernumber,
    f.salesorderlinenumber,
    f.orderquantity,
    f.unitprice,
    f.extendedamount,
    f.productstandardcost,
    f.totalproductcost,
    f.salesamount,
    f.taxamt,
    f.freight,
    f.orderdate,
    d.calendaryear,
    d.calendarquarter,
    d.englishmonthname AS month_name,
    d.monthnumberofyear AS month
FROM aw.fact_internet_sales f
JOIN aw.dim_date d ON f.orderdatekey = d.datekey;

-- Analytical dimension: product + territory (denormalized for readability)
CREATE TABLE analytics.product_dim AS
SELECT
    p.productkey,
    p.productalternatekey,
    pc.englishproductcategoryname AS product_category_name,
    ps.englishproductsubcategoryname AS product_subcategory_name,
    p.englishproductname,
    p.standardcost,
    p.listprice
FROM aw.dim_product p
JOIN aw.dim_product_subcategory ps ON p.productsubcategorykey = ps.productsubcategorykey
JOIN aw.dim_product_category pc ON ps.productcategorykey = pc.productcategorykey;

-- =====================================================================
-- 1. Revenue drivers: quantity vs price (AOV, items/order, price/item)
-- =====================================================================
CREATE TABLE analytics.q1_revenue_drivers AS
WITH order_metrics AS (
    SELECT
        f.salesordernumber,
        f.orderdate,
        f.calendaryear,
        f.month AS month,
        f.month_name AS month_name,
        SUM(f.orderquantity) AS line_items,
        SUM(f.salesamount) AS revenue,
        1 AS n_orders
    FROM analytics.fact_sales f
    GROUP BY f.salesordernumber, f.orderdate, f.calendaryear,
             f.month, f.month_name
)
SELECT
    month_name,
    month,
    SUM(line_items) AS total_line_items,
    SUM(revenue) AS revenue,
    ROUND(SUM(line_items) / SUM(n_orders)::numeric, 2) AS avg_items_per_order,
    ROUND(SUM(revenue) / NULLIF(SUM(line_items), 0), 2) AS avg_price_per_item,
    ROUND(SUM(revenue) / SUM(n_orders)::numeric, 2) AS aov
FROM order_metrics
GROUP BY month_name, month
ORDER BY month;

-- =====================================================================
-- 2. Contribution to change: YoY revenue growth by category/territory
-- =====================================================================
CREATE TABLE analytics.q2_contribution_to_change AS
WITH yearly AS (
    SELECT
        pd.product_category_name AS category,
        t.salesterritorygroup AS territory_group,
        t.salesterritorycountry AS territory,
        EXTRACT(YEAR FROM f.orderdate)::integer AS year,
        SUM(f.salesamount) AS revenue
    FROM aw.fact_internet_sales f
    JOIN aw.dim_product p ON f.productkey = p.productkey
    JOIN analytics.product_dim pd ON p.productkey = pd.productkey
    JOIN aw.dim_sales_territory t ON f.salesterritorykey = t.salesterritorykey
    GROUP BY pd.product_category_name, t.salesterritorygroup,
             t.salesterritorycountry, year
),
pivoted AS (
    SELECT
        category,
        territory,
        SUM(CASE WHEN year = 2012 THEN revenue ELSE 0 END) AS revenue_2012,
        SUM(CASE WHEN year = 2013 THEN revenue ELSE 0 END) AS revenue_2013
    FROM yearly
    WHERE year IN (2012, 2013)
    GROUP BY category, territory
),
grand AS (
    SELECT SUM(revenue_2012) AS total_2012, SUM(revenue_2013) AS total_2013
    FROM pivoted
)
SELECT
    p.category,
    p.territory,
    p.revenue_2012,
    p.revenue_2013,
    ROUND(p.revenue_2013 - p.revenue_2012, 2) AS absolute_change,
    ROUND(100.0 * (p.revenue_2013 - p.revenue_2012) / NULLIF(p.revenue_2012, 0), 2) AS relative_change_pct,
    ROUND(100.0 * (p.revenue_2013 - p.revenue_2012) / NULLIF(g.total_2013 - g.total_2012, 0), 2) AS contribution_to_change_pct
FROM pivoted p
CROSS JOIN grand g
ORDER BY contribution_to_change_pct DESC
LIMIT 15;

-- =====================================================================
-- 3. Pareto / concentration: product and customer revenue top-20%
-- =====================================================================
CREATE TABLE analytics.q3_pareto_concentration AS
WITH product_sales AS (
    SELECT
        p.productalternatekey AS product_key,
        pd.product_category_name AS category,
        SUM(f.salesamount) AS revenue
    FROM aw.fact_internet_sales f
    JOIN aw.dim_product p ON f.productkey = p.productkey
    JOIN analytics.product_dim pd ON p.productkey = pd.productkey
    GROUP BY p.productalternatekey, pd.product_category_name
),
ranked_products AS (
    SELECT *, ROW_NUMBER() OVER (ORDER BY revenue DESC) AS product_rank
    FROM product_sales
),
product_pareto AS (
    SELECT
        product_rank,
        revenue,
        category,
        ROUND(SUM(revenue) OVER (ORDER BY revenue DESC ROWS UNBOUNDED PRECEDING) /
        SUM(revenue) OVER () * 100.0, 2) AS cumulative_pct
    FROM ranked_products
),
customer_sales AS (
    SELECT
        c.customeralternatekey AS customer_key,
        SUM(f.salesamount) AS revenue
    FROM aw.fact_internet_sales f
    JOIN aw.dim_customer c ON f.customerkey = c.customerkey
    GROUP BY c.customeralternatekey
),
ranked_customers AS (
    SELECT *, ROW_NUMBER() OVER (ORDER BY revenue DESC) AS customer_rank
    FROM customer_sales
),
customer_pareto AS (
    SELECT
        customer_rank,
        revenue,
        ROUND(SUM(revenue) OVER (ORDER BY revenue DESC ROWS UNBOUNDED PRECEDING) /
        SUM(revenue) OVER () * 100.0, 2) AS cumulative_pct
    FROM ranked_customers
),
stats AS (
    SELECT
        (SELECT COUNT(*) FROM product_sales) AS n_products,
        (SELECT COUNT(*) FROM customer_sales) AS n_customers,
        (SELECT cumulative_pct FROM product_pareto
         ORDER BY product_rank = GREATEST(1, FLOOR(0.2 * (SELECT COUNT(*) FROM product_sales))::integer)
                   DESC LIMIT 1) AS product_top20_pct,
        (SELECT cumulative_pct FROM customer_pareto
         ORDER BY customer_rank = GREATEST(1, FLOOR(0.2 * (SELECT COUNT(*) FROM customer_sales))::integer)
                  DESC LIMIT 1) AS customer_top20_pct
)
SELECT * FROM stats;

-- =====================================================================
-- 4. Customer segmentation (RFM-based)
-- =====================================================================
CREATE TABLE analytics.q4_customer_segments AS
WITH customer_metrics AS (
    SELECT
        c.customerkey,
        c.customeralternatekey AS customer_key,
        COUNT(DISTINCT f.salesordernumber) AS n_orders,
        SUM(f.salesamount) AS total_revenue,
        SUM(f.orderquantity) AS total_quantity,
        MAX(f.orderdate) AS last_order_date,
        SUM(f.salesamount) / NULLIF(COUNT(DISTINCT f.salesordernumber), 0) AS avg_order_value
    FROM aw.fact_internet_sales f
    JOIN aw.dim_customer c ON f.customerkey = c.customerkey
    GROUP BY c.customerkey, c.customeralternatekey
),
scored AS (
    SELECT *,
        NTILE(5) OVER (ORDER BY total_revenue) AS revenue_quintile,
        NTILE(5) OVER (ORDER BY n_orders) AS frequency_quintile,
        -- Higher recency score = more recent purchase.
        NTILE(5) OVER (ORDER BY last_order_date ASC) AS recency_quintile
    FROM customer_metrics
)
SELECT
    customer_key,
    total_revenue,
    n_orders,
    avg_order_value,
    last_order_date,
    revenue_quintile,
    frequency_quintile,
    recency_quintile,
    CASE
        WHEN revenue_quintile = 5 AND frequency_quintile >= 4 AND recency_quintile >= 4 THEN 'Champions'
        WHEN revenue_quintile = 5 AND frequency_quintile >= 3 AND recency_quintile >= 3 THEN 'Loyal High-Spend'
        WHEN revenue_quintile >= 4 AND recency_quintile >= 4 THEN 'Recent High-Value'
        WHEN recency_quintile <= 2 AND (frequency_quintile >= 3 OR revenue_quintile >= 4) THEN 'At-Risk'
        WHEN recency_quintile <= 2 AND frequency_quintile <= 2 THEN 'Lost'
        WHEN frequency_quintile >= 4 AND revenue_quintile <= 2 THEN 'Frequent Low-Spend'
        ELSE 'Regular'
    END AS segment,
    CASE WHEN n_orders > 1 THEN 'repeat' ELSE 'first-time' END AS txn_type
FROM scored;

-- =====================================================================
-- 5. Revenue vs margin: where volume masks weak performance
-- =====================================================================
CREATE TABLE analytics.q5_revenue_vs_margin AS
SELECT
    pd.product_category_name AS category,
    pd.product_subcategory_name AS subcategory,
    SUM(f.salesamount) AS revenue,
    SUM(f.totalproductcost) AS total_cost,
    SUM(f.salesamount - f.totalproductcost) AS gross_profit,
    ROUND(100.0 * SUM(f.salesamount - f.totalproductcost) / NULLIF(SUM(f.salesamount), 0), 2) AS gross_margin_pct,
    SUM(f.orderquantity) AS units_sold,
    ROUND(SUM(f.salesamount) / NULLIF(SUM(f.orderquantity), 0), 2) AS avg_price_per_unit
FROM aw.fact_internet_sales f
JOIN aw.dim_product p ON f.productkey = p.productkey
JOIN analytics.product_dim pd ON p.productkey = pd.productkey
GROUP BY pd.product_category_name, pd.product_subcategory_name
ORDER BY revenue DESC;

COMMIT;
