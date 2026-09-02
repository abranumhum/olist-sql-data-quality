#!/usr/bin/env bash
set -euo pipefail

# Olist SQL Data Quality Pipeline
# Loads 9 CSVs, runs quality checks, builds typed tables, and computes analysis.
#
# Requires: PostgreSQL with psql, libpq env vars set (PGHOST, PGPORT, PGDATABASE, PGUSER)

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PSQL_BIN="${PSQL_BIN:-psql}"

for variable in PGHOST PGPORT PGDATABASE PGUSER; do
    [[ -n ${!variable:-} ]] || { printf 'Set %s for the PostgreSQL connection.\n' "$variable" >&2; exit 2; }
done

# 1. Load schema
"$PSQL_BIN" -X -v ON_ERROR_STOP=1 -f "$ROOT_DIR/sql/01_load.sql"

# 2. Load CSVs into raw tables
for table in category_translation customers geolocation orders order_items payments products reviews sellers; do
    csv="$ROOT_DIR/data/raw/${table}.csv"
    [[ -f "$csv" ]] || { echo "Missing: $csv" >&2; exit 2; }
    "$PSQL_BIN" -X -v ON_ERROR_STOP=1 -c "\copy raw.${table} FROM '$csv' WITH (FORMAT csv, HEADER true)"
    echo "OK: raw.${table} loaded"
done

# 3. Run SQL pipeline
for sql_file in 02_quality_checks.sql 03_cleaning.sql 04_analysis.sql; do
    "$PSQL_BIN" -X -v ON_ERROR_STOP=1 -f "$ROOT_DIR/sql/$sql_file"
    echo "OK: $sql_file"
done

# 4. Export reports
"$PSQL_BIN" -X -t -c "\copy (SELECT * FROM analytics.dq_summary) TO '$ROOT_DIR/reports/dq_summary.csv' WITH (FORMAT csv, HEADER true)"
"$PSQL_BIN" -X -t -c "\copy (SELECT * FROM analytics.reconciliation_summary) TO '$ROOT_DIR/reports/reconciliation_summary.csv' WITH (FORMAT csv, HEADER true)"
"$PSQL_BIN" -X -t -c "\copy (SELECT * FROM analytics.kpi_summary) TO '$ROOT_DIR/reports/kpi_summary.csv' WITH (FORMAT csv, HEADER true)"
"$PSQL_BIN" -X -t -c "\copy (SELECT * FROM analytics.business_summary) TO '$ROOT_DIR/reports/business_summary.csv' WITH (FORMAT csv, HEADER true)"

# Export analysis results
for table in monthly_sales category_performance seller_performance repeat_customer_summary delivery_review_summary order_value_distribution payment_method_summary worst_delivery_delays; do
    "$PSQL_BIN" -X -t -c "\copy (SELECT * FROM analytics.${table}) TO '$ROOT_DIR/reports/${table}.csv' WITH (FORMAT csv, HEADER true)"
done

# 5. Print summary
echo ""
echo "=== Pipeline complete ==="
echo "Raw rows:     $( "$PSQL_BIN" -X -t -c "SELECT (SELECT count(*) FROM raw.orders) + (SELECT count(*) FROM raw.order_items) + (SELECT count(*) FROM raw.payments) + (SELECT count(*) FROM raw.reviews) + (SELECT count(*) FROM raw.customers) + (SELECT count(*) FROM raw.sellers) + (SELECT count(*) FROM raw.products) + (SELECT count(*) FROM raw.geolocation) + (SELECT count(*) FROM raw.category_translation)" | tr -d ' ' )"
echo "Analytical orders: $( "$PSQL_BIN" -X -t -c "SELECT count(DISTINCT order_id) FROM analytics.orders" | tr -d ' ' )"
echo "DQ issues:    $( "$PSQL_BIN" -X -t -c "SELECT sum(issue_count) FROM analytics.dq_summary" | tr -d ' ' )"
echo "Payment mismatches: $( "$PSQL_BIN" -X -t -c "SELECT mismatched_orders FROM analytics.reconciliation_summary" | tr -d ' ' )"
