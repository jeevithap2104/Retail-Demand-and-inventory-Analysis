DROP TABLE IF EXISTS sales;
DROP TABLE IF EXISTS inventory_daily;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS stores;

CREATE TABLE stores (
    store_id            TEXT PRIMARY KEY,
    store_name          TEXT NOT NULL,
    region              TEXT NOT NULL,
    store_type          TEXT NOT NULL,
    sqft                INTEGER,
    opened_date         DATE,
    popularity_index    REAL
);

CREATE TABLE products (
    product_id          TEXT PRIMARY KEY,
    product_name        TEXT NOT NULL,
    category            TEXT NOT NULL,
    subcategory         TEXT NOT NULL,
    unit_cost           REAL NOT NULL,
    unit_price          REAL NOT NULL,
    supplier_id         TEXT,
    lead_time_days      INTEGER,
    base_daily_demand   REAL
);

-- One row per store/product/day: tracks the inventory position and whether
-- demand exceeded available stock (stockout_flag).
CREATE TABLE inventory_daily (
    date                DATE NOT NULL,
    store_id            TEXT NOT NULL REFERENCES stores(store_id),
    product_id          TEXT NOT NULL REFERENCES products(product_id),
    opening_stock       INTEGER NOT NULL,
    received_qty        INTEGER NOT NULL,
    sold_qty            INTEGER NOT NULL,
    closing_stock       INTEGER NOT NULL,
    reorder_point       INTEGER NOT NULL,
    reorder_qty         INTEGER NOT NULL,
    stockout_flag       INTEGER NOT NULL,  -- 1/0 (BOOLEAN on PG)
    PRIMARY KEY (date, store_id, product_id)
);

-- Transaction-level sales; one row per fulfilled sale event (only exists
-- when sold_qty > 0 for that store/product/day in inventory_daily).
CREATE TABLE sales (
    sale_id             INTEGER PRIMARY KEY,
    date                DATE NOT NULL,
    store_id            TEXT NOT NULL REFERENCES stores(store_id),
    product_id          TEXT NOT NULL REFERENCES products(product_id),
    quantity            INTEGER NOT NULL,
    unit_price          REAL NOT NULL,
    discount_pct        REAL NOT NULL,
    revenue             REAL NOT NULL
);

CREATE INDEX idx_sales_date ON sales(date);
CREATE INDEX idx_sales_store ON sales(store_id);
CREATE INDEX idx_sales_product ON sales(product_id);
CREATE INDEX idx_inventory_date ON inventory_daily(date);
CREATE INDEX idx_inventory_store_product ON inventory_daily(store_id, product_id);