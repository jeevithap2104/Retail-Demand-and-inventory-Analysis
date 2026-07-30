# Entity Relationship Diagram

```
 stores                     products
 ---------------------      ---------------------
 store_id        PK    ┐    product_id       PK    ┐
 store_name             │    product_name           │
 region                 │    category                │
 store_type             │    subcategory              │
 sqft                    │    unit_cost                 │
 opened_date              │    unit_price                 │
 popularity_index          │    supplier_id                │
                            │    lead_time_days              │
                            │    base_daily_demand             │
                            │                                    │
                            ▼                                    ▼
                    inventory_daily                          sales
              -----------------------------          -----------------------------
              date                    PK,FK1          sale_id               PK
              store_id                PK,FK2 -> stores.store_id
              product_id              PK,FK3 -> products.product_id
              opening_stock                            date                  FK -> (implicit, no daily grain)
              received_qty                             store_id              FK -> stores.store_id
              sold_qty                                 product_id            FK -> products.product_id
              closing_stock                            quantity
              reorder_point                            unit_price
              reorder_qty                              discount_pct
              stockout_flag                            revenue
```

**Grain**
- `inventory_daily`: one row per (date, store, product) — the daily inventory position.
- `sales`: one row per fulfilled sale event (only exists where `sold_qty > 0` in `inventory_daily` for that date/store/product).

**Relationships**
- `stores.store_id` 1—* `inventory_daily.store_id`
- `stores.store_id` 1—* `sales.store_id`
- `products.product_id` 1—* `inventory_daily.product_id`
- `products.product_id` 1—* `sales.product_id`

For Power BI, this same model is exported as a proper star schema
(`data/processed/dim_*.csv` + `fact_*.csv`) — see `powerbi/POWERBI_GUIDE.md`.
