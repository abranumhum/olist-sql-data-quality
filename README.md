# Olist SQL Data Quality

PostgreSQL project for exploring the **Olist Brazilian E-Commerce** dataset from
Kaggle: approximately 100,000 orders across 9 related CSV files. The focus is SQL
profiling, relational data quality, reconciliation, and practical business analysis.

## Interpretation principle

The project does **not** treat every unusual record as an error to correct. Late
deliveries, unavailable orders, split payments, repeated reviews, and missing catalog
attributes may be valid business or source-system events. `raw` remains unchanged;
`analytics` means *typed and safe to query consistently*, not *repaired source data*.
Suspected issues remain visible in the DQ and reconciliation reports.

## Dataset and grain

The main relationships are:

```text
customers 1 ── 1 orders 1 ── N order_items N ── 1 products
                         │              └──── N ── 1 sellers
                         ├──── 1 ── N payments
                         └──── 1 ── N reviews
products N ── 1 category_translation
geolocation: repeated observations by zip-code prefix
```

`orders` is at order grain. `order_items`, `payments`, and `reviews` can contain
multiple rows per order. Analytical queries therefore distinguish `orders`
(`COUNT(DISTINCT order_id)`) from `line_items` (`COUNT(*)`).

## What the project does

1. Loads all 9 CSVs into PostgreSQL tables in the `raw` schema.
2. Checks critical NULLs, duplicate business keys, orphan rows, timelines,
   numeric ranges, review scores, and order statuses.
3. Creates typed analytical tables using ordinary SQL expressions. `DISTINCT ON`
   is limited to relationships where analysis requires one deterministic row per key;
   source duplicates remain documented rather than deleted from `raw`.
4. Reconciles payments against `price + freight_value` after aggregating both
   child tables to order grain. This avoids an items × payments fan-out.
5. Produces 8 analyses and exports compact CSV reports.

## Real data-quality findings

| Finding | Count | Possible explanation |
|---|---:|---|
| Delivered after estimated date | 7,827 | Logistics delays or optimistic estimates; 8.11% of orders with both dates |
| Products without category | 610 | Incomplete product catalog attributes |
| Extra review rows per order | 551 | Updated/repeated review records rather than a strict one-review relationship |
| Payment/item total mismatch over R$0.01 | 303 | Adjustments, split-payment behavior, refunds, or source inconsistencies |
| Delivery timestamp before carrier handoff | 23 | Event timestamps recorded out of sequence |
| Zero-value payment rows | 9 | Voucher-covered or placeholder payment entries |
| Delivered orders without delivery timestamp | 8 | Status/timestamp inconsistency |
| Products missing physical dimensions | 2 | Incomplete catalog metadata |

Reconciliation also finds 775 orders without item rows. Most are `unavailable` or
`canceled`, so they are retained and are not automatically treated as financial errors. One order
has no payment row. The 303 non-null mismatches average R$10.79; the largest is
R$182.81. These are observations, not proof of a specific root cause.

## Analysis outputs

- `monthly_sales`: order count, line items, product sales, freight, revenue
- `category_performance`: top categories with order and line-item counts
- `seller_performance`: top sellers by delivered revenue
- `repeat_customer_summary`: repeat behavior by `customer_unique_id`
- `delivery_review_summary`: delivery duration versus review score
- `order_value_distribution`: distribution after aggregating items to order grain
- `payment_method_summary`: payment usage, value, and installments
- `worst_delivery_delays`: five largest actual-versus-estimated gaps

Selected results:

- **98,197** revenue-eligible orders, **112,098** line items and **R$15.74M**
  item-and-freight revenue; AOV is **R$160.24**.
- Peak month: **2017-11**, with 7,421 orders and R$1.17M revenue.
- 2,801 customers made more than one delivered order (about 3.0%).
- Average delivery falls from 21.3 days for one-star reviews to 10.7 days for
  five-star reviews. This is correlation, not proof of causation.

## Run locally

```bash
uv sync

export PGHOST=127.0.0.1
export PGPORT=5432
export PGDATABASE=olist
export PGUSER=postgres
make sql
make test
```

The pipeline rebuilds only the project-owned `raw` and `analytics` schemas.

## Structure

```text
data/raw/   9 source CSV files
sql/        01_load.sql
            02_quality_checks.sql
            03_cleaning.sql          typed analytical layer; no source repair
            04_analysis.sql
scripts/    run_pipeline.sh
reports/    DQ, reconciliation, KPI, and analytical CSV outputs
tests/      test_pipeline.py (5 smoke/integration tests)
```

## Source and limitations

Source: [Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce).
The CSV snapshot adds `load_row_id` for deterministic loading. Data ends in 2018.
