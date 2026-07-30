"""
load_to_db.py
--------------
Loads the CSVs in data/raw/ into a SQLite database (retail.db) using the
schema defined in sql/01_schema.sql, then loads each table with pandas.

Run:
    python load_to_db.py
"""

import os
import sqlite3
import pandas as pd

BASE_DIR = os.path.dirname(__file__)
RAW_DIR = os.path.join(BASE_DIR, "..", "data", "raw")
SQL_DIR = os.path.join(BASE_DIR, "..", "sql")
DB_PATH = os.path.join(BASE_DIR, "..", "retail.db")


def main():
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)

    conn = sqlite3.connect(DB_PATH)

    with open(os.path.join(SQL_DIR, "01_schema.sql")) as f:
        schema_sql = f.read()
    conn.executescript(schema_sql)

    tables = {
        "stores": "stores.csv",
        "products": "products.csv",
        "inventory_daily": "inventory_daily.csv",
        "sales": "sales.csv",
    }

    for table, filename in tables.items():
        df = pd.read_csv(os.path.join(RAW_DIR, filename))
        df.to_sql(table, conn, if_exists="append", index=False)
        print(f"Loaded {len(df):,} rows into '{table}'")

    conn.commit()
    conn.close()
    print(f"\nDatabase built at: {os.path.abspath(DB_PATH)}")


if __name__ == "__main__":
    main()
