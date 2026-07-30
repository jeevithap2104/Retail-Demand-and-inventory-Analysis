-- QUERY: monthly_revenue_by_category
-- Aggregation + JOIN: total revenue and units sold per category per month.
SELECT
    strftime('%Y-%m', s.date)          AS sales_month,
    p.category,
    SUM(s.quantity)                    AS units_sold,
    ROUND(SUM(s.revenue), 2)           AS total_revenue,
    ROUND(AVG(s.revenue / s.quantity), 2) AS avg_selling_price
FROM sales s
JOIN products p ON p.product_id = s.product_id
GROUP BY sales_month, p.category
ORDER BY sales_month, total_revenue DESC;


-- QUERY: top_10_products_by_revenue
-- Aggregation + JOIN + window function: rank products by total revenue.
SELECT
    p.product_id,
    p.product_name,
    p.category,
    ROUND(SUM(s.revenue), 2)   AS total_revenue,
    SUM(s.quantity)            AS units_sold,
    RANK() OVER (ORDER BY SUM(s.revenue) DESC) AS revenue_rank
FROM sales s
JOIN products p ON p.product_id = s.product_id
GROUP BY p.product_id, p.product_name, p.category
ORDER BY revenue_rank
LIMIT 10;


-- QUERY: store_ranking_by_region
-- JOIN + aggregation + window function: rank stores within their region.
SELECT
    st.region,
    st.store_id,
    st.store_name,
    ROUND(SUM(s.revenue), 2) AS total_revenue,
    RANK() OVER (PARTITION BY st.region ORDER BY SUM(s.revenue) DESC) AS rank_in_region
FROM sales s
JOIN stores st ON st.store_id = s.store_id
GROUP BY st.region, st.store_id, st.store_name
ORDER BY st.region, rank_in_region;


-- QUERY: monthly_revenue_running_total
-- Window function: cumulative (running total) revenue per store by month.
WITH monthly AS (
    SELECT
        store_id,
        strftime('%Y-%m', date) AS sales_month,
        SUM(revenue) AS monthly_revenue
    FROM sales
    GROUP BY store_id, sales_month
)
SELECT
    store_id,
    sales_month,
    ROUND(monthly_revenue, 2) AS monthly_revenue,
    ROUND(SUM(monthly_revenue) OVER (
        PARTITION BY store_id ORDER BY sales_month
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ), 2) AS running_total_revenue
FROM monthly
ORDER BY store_id, sales_month;


-- QUERY: seven_day_moving_avg_demand
-- Window function: 7-day moving average of daily units sold, per product.
WITH daily AS (
    SELECT
        product_id,
        date,
        SUM(sold_qty) AS daily_units
    FROM inventory_daily
    GROUP BY product_id, date
)
SELECT
    product_id,
    date,
    daily_units,
    ROUND(AVG(daily_units) OVER (
        PARTITION BY product_id ORDER BY date
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ), 2) AS moving_avg_7d
FROM daily
ORDER BY product_id, date;


-- QUERY: month_over_month_growth
-- Window function LAG(): month-over-month revenue growth rate, company-wide.
WITH monthly AS (
    SELECT
        strftime('%Y-%m', date) AS sales_month,
        SUM(revenue) AS monthly_revenue
    FROM sales
    GROUP BY sales_month
)
SELECT
    sales_month,
    ROUND(monthly_revenue, 2) AS monthly_revenue,
    ROUND(LAG(monthly_revenue) OVER (ORDER BY sales_month), 2) AS prior_month_revenue,
    ROUND(
        100.0 * (monthly_revenue - LAG(monthly_revenue) OVER (ORDER BY sales_month))
        / NULLIF(LAG(monthly_revenue) OVER (ORDER BY sales_month), 0)
    , 2) AS mom_growth_pct
FROM monthly
ORDER BY sales_month;


-- QUERY: stockout_rate_by_product
-- Aggregation + JOIN: how often each product was out of stock when demand hit.
SELECT
    p.product_id,
    p.product_name,
    p.category,
    COUNT(*)                                   AS days_tracked,
    SUM(i.stockout_flag)                       AS stockout_days,
    ROUND(100.0 * SUM(i.stockout_flag) / COUNT(*), 2) AS stockout_rate_pct
FROM inventory_daily i
JOIN products p ON p.product_id = i.product_id
GROUP BY p.product_id, p.product_name, p.category
ORDER BY stockout_rate_pct DESC;


-- QUERY: days_since_last_restock
-- Window function: for each store/product/day, days elapsed since the last
-- delivery (received_qty > 0), using a gap-and-island style LAG pattern.
WITH restocks AS (
    SELECT
        store_id,
        product_id,
        date,
        received_qty,
        CASE WHEN received_qty > 0 THEN date END AS restock_date
    FROM inventory_daily
),
carried AS (
    SELECT
        store_id,
        product_id,
        date,
        MAX(restock_date) OVER (
            PARTITION BY store_id, product_id ORDER BY date
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS last_restock_date
    FROM restocks
)
SELECT
    store_id,
    product_id,
    date,
    last_restock_date,
    CAST(julianday(date) - julianday(last_restock_date) AS INTEGER) AS days_since_restock
FROM carried
WHERE last_restock_date IS NOT NULL
ORDER BY store_id, product_id, date;


-- QUERY: inventory_turnover_by_store
-- JOIN + aggregation: turnover ratio = COGS sold / average inventory value.
WITH cogs AS (
    SELECT
        s.store_id,
        SUM(s.quantity * p.unit_cost) AS total_cogs
    FROM sales s
    JOIN products p ON p.product_id = s.product_id
    GROUP BY s.store_id
),
avg_inv AS (
    SELECT
        i.store_id,
        AVG(i.closing_stock * p.unit_cost) AS avg_inventory_value
    FROM inventory_daily i
    JOIN products p ON p.product_id = i.product_id
    GROUP BY i.store_id
)
SELECT
    c.store_id,
    ROUND(c.total_cogs, 2)        AS total_cogs,
    ROUND(a.avg_inventory_value, 2) AS avg_inventory_value,
    ROUND(c.total_cogs / NULLIF(a.avg_inventory_value, 0), 2) AS inventory_turnover_ratio
FROM cogs c
JOIN avg_inv a ON a.store_id = c.store_id
ORDER BY inventory_turnover_ratio DESC;


-- QUERY: abc_product_classification
-- Window function: cumulative revenue % to classify products A/B/C
-- (A = top 80% of revenue, B = next 15%, C = remaining 5%) — classic
-- inventory-management Pareto analysis.
WITH product_revenue AS (
    SELECT
        p.product_id,
        p.product_name,
        SUM(s.revenue) AS total_revenue
    FROM sales s
    JOIN products p ON p.product_id = s.product_id
    GROUP BY p.product_id, p.product_name
),
ranked AS (
    SELECT
        product_id,
        product_name,
        total_revenue,
        SUM(total_revenue) OVER (ORDER BY total_revenue DESC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_revenue,
        SUM(total_revenue) OVER () AS grand_total_revenue
    FROM product_revenue
)
SELECT
    product_id,
    product_name,
    ROUND(total_revenue, 2) AS total_revenue,
    ROUND(100.0 * running_revenue / grand_total_revenue, 2) AS cumulative_revenue_pct,
    CASE
        WHEN 100.0 * running_revenue / grand_total_revenue <= 80 THEN 'A'
        WHEN 100.0 * running_revenue / grand_total_revenue <= 95 THEN 'B'
        ELSE 'C'
    END AS abc_class
FROM ranked
ORDER BY total_revenue DESC;