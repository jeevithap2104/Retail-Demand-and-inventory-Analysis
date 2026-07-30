"""
analysis.py
-----------
Runs every labeled query in sql/02_analysis_queries.sql against retail.db,
exports each result to outputs/query_results/<name>.csv, generates a handful
of summary charts, and runs a validation pass that reconciles query outputs
against the raw tables (row counts, totals, null checks, and range checks).

Run:
    python analysis.py
"""

import os
import re
import sqlite3
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

BASE_DIR = os.path.dirname(__file__)
SQL_DIR = os.path.join(BASE_DIR, "..", "sql")
DB_PATH = os.path.join(BASE_DIR, "..", "retail.db")
RESULTS_DIR = os.path.join(BASE_DIR, "..", "outputs", "query_results")
CHARTS_DIR = os.path.join(BASE_DIR, "..", "outputs", "charts")
VALIDATION_PATH = os.path.join(BASE_DIR, "..", "outputs", "validation_report.txt")

os.makedirs(RESULTS_DIR, exist_ok=True)
os.makedirs(CHARTS_DIR, exist_ok=True)


def parse_queries(sql_text: str) -> dict:
    """Split the .sql file into {name: query} using '-- QUERY: <name>' markers."""
    parts = re.split(r"--\s*QUERY:\s*(\w+)", sql_text)
    queries = {}
    # parts[0] is the file header/comments before the first marker
    for i in range(1, len(parts), 2):
        name = parts[i].strip()
        body = parts[i + 1]
        queries[name] = body.strip().rstrip(";")
    return queries


def run_queries(conn, queries: dict) -> dict:
    results = {}
    for name, sql in queries.items():
        df = pd.read_sql_query(sql, conn)
        df.to_csv(os.path.join(RESULTS_DIR, f"{name}.csv"), index=False)
        results[name] = df
        print(f"  {name:<32} -> {len(df):>6,} rows")
    return results


def make_charts(results: dict):
    # 1. Monthly revenue trend (company-wide)
    mom = results["month_over_month_growth"]
    fig, ax = plt.subplots(figsize=(9, 4.5))
    ax.plot(mom["sales_month"], mom["monthly_revenue"], marker="o", color="#2563eb")
    ax.set_title("Monthly Revenue Trend")
    ax.set_xlabel("Month")
    ax.set_ylabel("Revenue ($)")
    ax.tick_params(axis="x", rotation=45)
    fig.tight_layout()
    fig.savefig(os.path.join(CHARTS_DIR, "monthly_revenue_trend.png"), dpi=150)
    plt.close(fig)

    # 2. Top 10 products by revenue
    top10 = results["top_10_products_by_revenue"]
    fig, ax = plt.subplots(figsize=(9, 5))
    ax.barh(top10["product_name"][::-1], top10["total_revenue"][::-1], color="#059669")
    ax.set_title("Top 10 Products by Revenue")
    ax.set_xlabel("Revenue ($)")
    fig.tight_layout()
    fig.savefig(os.path.join(CHARTS_DIR, "top_10_products.png"), dpi=150)
    plt.close(fig)

    # 3. Stockout rate by category (aggregated from per-product query)
    stockout = results["stockout_rate_by_product"]
    by_cat = stockout.groupby("category")["stockout_rate_pct"].mean().sort_values(ascending=False)
    fig, ax = plt.subplots(figsize=(7, 4.5))
    ax.bar(by_cat.index, by_cat.values, color="#dc2626")
    ax.set_title("Average Stockout Rate by Category")
    ax.set_ylabel("Stockout Rate (%)")
    ax.tick_params(axis="x", rotation=30)
    fig.tight_layout()
    fig.savefig(os.path.join(CHARTS_DIR, "stockout_rate_by_category.png"), dpi=150)
    plt.close(fig)

    # 4. Inventory turnover by store
    turnover = results["inventory_turnover_by_store"]
    fig, ax = plt.subplots(figsize=(8, 4.5))
    ax.bar(turnover["store_id"], turnover["inventory_turnover_ratio"], color="#7c3aed")
    ax.set_title("Inventory Turnover Ratio by Store")
    ax.set_ylabel("Turnover Ratio")
    fig.tight_layout()
    fig.savefig(os.path.join(CHARTS_DIR, "inventory_turnover_by_store.png"), dpi=150)
    plt.close(fig)

    print(f"\nSaved 4 charts to {os.path.abspath(CHARTS_DIR)}")


def validate(conn, results: dict) -> list:
    """Reconcile query outputs against the raw tables. Returns a list of
    (check_name, passed: bool, detail: str) tuples."""
    checks = []

    raw_sales_total = pd.read_sql_query("SELECT ROUND(SUM(revenue), 2) AS t FROM sales", conn)["t"][0]
    query_total = round(results["month_over_month_growth"]["monthly_revenue"].sum(), 2)
    checks.append((
        "Total revenue reconciliation (sales table vs monthly rollup)",
        abs(raw_sales_total - query_total) < 1.0,
        f"raw={raw_sales_total:,.2f}  query={query_total:,.2f}"
    ))

    top10 = results["top_10_products_by_revenue"]
    checks.append((
        "Top 10 products query returns exactly 10 rows",
        len(top10) == 10,
        f"rows={len(top10)}"
    ))
    checks.append((
        "Top 10 products revenue is non-increasing (rank order correct)",
        top10["total_revenue"].is_monotonic_decreasing,
        "revenue_rank matches SUM(revenue) DESC"
    ))

    abc = results["abc_product_classification"]
    checks.append((
        "ABC classification covers every product",
        len(abc) == pd.read_sql_query("SELECT COUNT(*) AS c FROM products", conn)["c"][0],
        f"abc_rows={len(abc)}"
    ))
    checks.append((
        "ABC cumulative revenue % reaches ~100% at the last row",
        abs(abc["cumulative_revenue_pct"].iloc[-1] - 100.0) < 0.5,
        f"final_pct={abc['cumulative_revenue_pct'].iloc[-1]}"
    ))

    stockout = results["stockout_rate_by_product"]
    checks.append((
        "Stockout rate is within [0, 100] for every product",
        stockout["stockout_rate_pct"].between(0, 100).all(),
        f"min={stockout['stockout_rate_pct'].min()}  max={stockout['stockout_rate_pct'].max()}"
    ))

    inv_negative = pd.read_sql_query(
        "SELECT COUNT(*) AS c FROM inventory_daily WHERE closing_stock < 0", conn
    )["c"][0]
    checks.append((
        "No negative closing stock in inventory_daily",
        inv_negative == 0,
        f"negative_rows={inv_negative}"
    ))

    for df_name in ["stores", "products", "sales", "inventory_daily"]:
        n_nulls = pd.read_sql_query(f"SELECT * FROM {df_name}", conn).isnull().sum().sum()
        checks.append((
            f"No unexpected NULLs in '{df_name}'",
            n_nulls == 0,
            f"null_cells={n_nulls}"
        ))

    return checks


def main():
    conn = sqlite3.connect(DB_PATH)

    with open(os.path.join(SQL_DIR, "02_analysis_queries.sql")) as f:
        sql_text = f.read()
    queries = parse_queries(sql_text)

    print(f"Running {len(queries)} analysis queries against {DB_PATH}...\n")
    results = run_queries(conn, queries)

    make_charts(results)

    print("\nValidating results against source tables...")
    checks = validate(conn, results)

    lines = ["VALIDATION REPORT", "=" * 60]
    n_pass = 0
    for name, passed, detail in checks:
        status = "PASS" if passed else "FAIL"
        n_pass += int(passed)
        lines.append(f"[{status}] {name}\n        {detail}")
    lines.append("=" * 60)
    lines.append(f"{n_pass}/{len(checks)} checks passed")

    report = "\n".join(lines)
    print("\n" + report)

    with open(VALIDATION_PATH, "w") as f:
        f.write(report + "\n")

    conn.close()


if __name__ == "__main__":
    main()
