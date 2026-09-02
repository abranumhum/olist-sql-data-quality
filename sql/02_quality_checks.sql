-- 02_quality_checks.sql
-- Simple data-quality checks on the 9 raw Olist tables.
BEGIN;

CREATE TABLE analytics.dq_summary AS
SELECT check_name, issue_count
FROM (
    -- NULL checks in critical fields
    SELECT 'orders: NULL order_id' AS check_name, count(*) AS issue_count FROM raw.orders WHERE order_id IS NULL
    UNION ALL SELECT 'orders: NULL customer_id', count(*) FROM raw.orders WHERE customer_id IS NULL
    UNION ALL SELECT 'orders: NULL purchase timestamp', count(*) FROM raw.orders WHERE order_purchase_timestamp IS NULL
    UNION ALL SELECT 'delivered orders: NULL delivery timestamp', count(*) FROM raw.orders WHERE order_status = 'delivered' AND order_delivered_customer_date IS NULL
    UNION ALL SELECT 'order_items: NULL order_id', count(*) FROM raw.order_items WHERE order_id IS NULL
    UNION ALL SELECT 'order_items: NULL product_id', count(*) FROM raw.order_items WHERE product_id IS NULL
    UNION ALL SELECT 'order_items: NULL seller_id', count(*) FROM raw.order_items WHERE seller_id IS NULL
    UNION ALL SELECT 'products: missing category', count(*) FROM raw.products WHERE product_category_name IS NULL OR trim(product_category_name) = ''
    UNION ALL SELECT 'products: missing dimensions', count(*) FROM raw.products WHERE product_weight_g IS NULL OR product_length_cm IS NULL OR product_height_cm IS NULL OR product_width_cm IS NULL

    -- Duplicate business keys
    UNION ALL SELECT 'orders: duplicate order_id', count(*) - count(DISTINCT order_id) FROM raw.orders
    UNION ALL SELECT 'customers: duplicate customer_id', count(*) - count(DISTINCT customer_id) FROM raw.customers
    UNION ALL SELECT 'products: duplicate product_id', count(*) - count(DISTINCT product_id) FROM raw.products
    UNION ALL SELECT 'sellers: duplicate seller_id', count(*) - count(DISTINCT seller_id) FROM raw.sellers
    UNION ALL SELECT 'order_items: duplicate order/item key', count(*) - count(DISTINCT (order_id, order_item_id)) FROM raw.order_items
    UNION ALL SELECT 'reviews: extra rows per order', count(*) - count(DISTINCT order_id) FROM raw.reviews

    -- FK / orphan checks
    UNION ALL SELECT 'order_items: order not found', count(*) FROM raw.order_items i LEFT JOIN raw.orders o USING (order_id) WHERE o.order_id IS NULL
    UNION ALL SELECT 'order_items: product not found', count(*) FROM raw.order_items i LEFT JOIN raw.products p USING (product_id) WHERE p.product_id IS NULL
    UNION ALL SELECT 'order_items: seller not found', count(*) FROM raw.order_items i LEFT JOIN raw.sellers s USING (seller_id) WHERE s.seller_id IS NULL
    UNION ALL SELECT 'payments: order not found', count(*) FROM raw.payments p LEFT JOIN raw.orders o USING (order_id) WHERE o.order_id IS NULL
    UNION ALL SELECT 'reviews: order not found', count(*) FROM raw.reviews r LEFT JOIN raw.orders o USING (order_id) WHERE o.order_id IS NULL
    UNION ALL SELECT 'orders: customer not found', count(*) FROM raw.orders o LEFT JOIN raw.customers c USING (customer_id) WHERE c.customer_id IS NULL

    -- Timeline checks
    UNION ALL SELECT 'timeline: delivery before purchase', count(*) FROM raw.orders
      WHERE order_delivered_customer_date IS NOT NULL AND order_purchase_timestamp IS NOT NULL
        AND order_delivered_customer_date::timestamp < order_purchase_timestamp::timestamp
    UNION ALL SELECT 'timeline: delivery before carrier handoff', count(*) FROM raw.orders
      WHERE order_delivered_customer_date IS NOT NULL AND order_delivered_carrier_date IS NOT NULL
        AND order_delivered_customer_date::timestamp < order_delivered_carrier_date::timestamp
    UNION ALL SELECT 'timeline: delivered after estimate', count(*) FROM raw.orders
      WHERE order_delivered_customer_date IS NOT NULL AND order_estimated_delivery_date IS NOT NULL
        AND order_delivered_customer_date::timestamp > order_estimated_delivery_date::timestamp

    -- Numeric and category checks
    UNION ALL SELECT 'order_items: negative price or freight', count(*) FROM raw.order_items WHERE price::numeric < 0 OR freight_value::numeric < 0
    UNION ALL SELECT 'payments: negative value', count(*) FROM raw.payments WHERE payment_value::numeric < 0
    UNION ALL SELECT 'payments: zero value', count(*) FROM raw.payments WHERE payment_value::numeric = 0
    UNION ALL SELECT 'reviews: score outside 1-5', count(*) FROM raw.reviews WHERE review_score::integer NOT BETWEEN 1 AND 5
    UNION ALL SELECT 'orders: unexpected status', count(*) FROM raw.orders
      WHERE order_status NOT IN ('pending','processing','shipped','delivered','canceled','unavailable','invoiced','payment_review','created','approved')
) checks
ORDER BY issue_count DESC, check_name;

-- Aggregate each child table before joining. This avoids an items × payments fan-out.
CREATE TABLE analytics.reconciliation_detail AS
WITH item_totals AS (
    SELECT order_id, sum(price::numeric + freight_value::numeric) AS item_total
    FROM raw.order_items
    GROUP BY order_id
),
payment_totals AS (
    SELECT order_id, sum(payment_value::numeric) AS payment_total
    FROM raw.payments
    GROUP BY order_id
)
SELECT
    o.order_id,
    i.item_total,
    p.payment_total,
    round(p.payment_total - i.item_total, 2) AS difference
FROM raw.orders o
LEFT JOIN item_totals i USING (order_id)
LEFT JOIN payment_totals p USING (order_id);

CREATE TABLE analytics.reconciliation_summary AS
SELECT
    count(*) AS total_orders,
    count(*) FILTER (WHERE abs(difference) <= 0.01) AS matched_orders,
    count(*) FILTER (WHERE abs(difference) > 0.01) AS mismatched_orders,
    count(*) FILTER (WHERE payment_total IS NULL) AS orders_without_payment,
    count(*) FILTER (WHERE item_total IS NULL) AS orders_without_items,
    round(avg(abs(difference)) FILTER (WHERE abs(difference) > 0.01), 2) AS avg_mismatch_brl,
    round(max(abs(difference)), 2) AS max_mismatch_brl
FROM analytics.reconciliation_detail;

COMMIT;
