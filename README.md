# Retail-Demand-and-inventory-Analysis
SQL-driven analysis of retail sales and inventory data — built to surface demand trends, stockout risk, and inventory efficiency, and to package the results into a Power BI dashboard. 
**Stack:** SQL (SQLite) · Python (pandas, matplotlib) · Excel · Power BI

## What this project does

1. **Simulates** a year of realistic store-level retail data: daily
   inventory positions (opening stock, replenishment, stockouts) and the
   transaction-level sales that result from them, across 10 stores and 25
   products.
2. **Analyzes** it with structured SQL — joins, aggregations, and window
   functions (`RANK`, `LAG`, running totals, moving averages) — to answer
   demand and inventory questions.
3. **Validates** every query's output against the source tables (row
   counts, revenue reconciliation, null checks, range checks) before
   trusting the numbers.
4. **Visualizes** the results as a Power BI dashboard (star schema +
   DAX measures provided) and as static charts for quick review.

## Project structure

```
retail-inventory-demand-analysis/
├── data/
│   ├── raw/                  # generated source CSVs (stores, products, sales, inventory)
│   └── processed/            # star schema for Power BI (dim_*.csv, fact_*.csv)
├── sql/
│   ├── 01_schema.sql         # table definitions + indexes
│   └── 02_analysis_queries.sql   # 10 labeled analysis queries
├── python/
│   ├── load_to_db.py         # loads CSVs into SQLite using the schema above
│   └── analysis.py           # runs every query, exports results + charts, validates output
├── powerbi/
│   ├── Dashboard.pbix        # PowerBI Dashboard with all key findings
│   └── dax_measures.txt      # DAX measures (revenue, YoY/MoM, turnover, stockout rate, etc.)
├── outputs/
│   ├── query_results/        # CSV output of every SQL query
│   └── charts/               # PNG charts generated from the query results
├── docs/
│   └── ERD.md                # entity relationship diagram
└── README.md
```

## SQL highlights (`sql/02_analysis_queries.sql`)

| Query | Technique | Answers |
|---|---|---|
| `monthly_revenue_by_category` | JOIN + GROUP BY | Revenue and units sold by category, by month |
| `top_10_products_by_revenue` | JOIN + `RANK() OVER` | Which products drive the most revenue |
| `store_ranking_by_region` | JOIN + `RANK() OVER (PARTITION BY region)` | How each store ranks within its region |
| `monthly_revenue_running_total` | `SUM() OVER (ORDER BY ... ROWS)` | Cumulative revenue trend per store |
| `seven_day_moving_avg_demand` | `AVG() OVER (ROWS BETWEEN 6 PRECEDING)` | Smoothed daily demand per product |
| `month_over_month_growth` | `LAG() OVER` | MoM revenue growth rate |
| `stockout_rate_by_product` | JOIN + GROUP BY | Which products run out of stock most often |
| `days_since_last_restock` | `MAX() OVER` (gap-filling) | How long since each store/product last received stock |
| `inventory_turnover_by_store` | JOIN + CTEs | COGS ÷ average inventory value, by store |
| `abc_product_classification` | `SUM() OVER` (cumulative %) | Pareto (A/B/C) classification of products by revenue |


## Key findings (from the generated dataset)

- **Footwear** is the top category by revenue (~$10.8M), more than
  double the next-highest category.
- The top single product by revenue is **Sandals Essential 2**
  (~$3.87M), and the top-performing store is **Store 009 (South
  region)** at ~$4.2M.
- Average stockout rate across all products is **2.1%** of tracked
  days; the worst-performing SKU (**Bedding Everyday 14**) sits at
  **5.3%**, a candidate for a higher reorder point or shorter supplier
  lead time.
- ABC analysis: **12 products (48%) drive 80% of revenue** (Class A),
  the classic Pareto pattern — inventory investment should concentrate
  there.
- Revenue shows a clear **holiday-season lift in Nov/Dec** and a dip in
  Jan/Feb, consistent with the seasonality built into demand.
